// Source-module mode: QuickJS module loader glue.
//
// Modules come from one of two places:
//  - a module image: precompiled bytecode plus a resolution table, built by
//    quicktui_build_image() and usually embedded in the executable; or
//  - the loader realm: a second JSContext in the application's runtime that
//    holds Sucrase and js/loader/policy.js. It resolves specifiers and produces
//    module source, which is compiled in the application realm and cached as
//    bytecode by src/modules.zig. Only strings cross between the two realms.
// With both configured, the image wins and the realm handles the rest.
// CommonJS packages run in js/loader/cjs.js behind ES module facades.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "quickjs.h"
#include "module_loader.h"

typedef struct {
    int active;
    const char *root;           // checkout for the loader realm; "" = image only
    const char *entry;
    int demo_assets;
    int hosted;
    const char *sucrase; size_t sucrase_len;
    const char *policy; size_t policy_len;
    const char *commonjs; size_t commonjs_len;
    const char *cache_dir;
    int trace;
    const uint8_t *image; size_t image_len; // must outlive every runtime
    int record;                 // quicktui_build_image is running
    const char *depfile;        // build mode: Makefile depfile of every file read, or ""
    int quiet;                  // build mode: no summary line (zig build treats stderr as failure)
} QtModuleConfig;

// Implemented in src/modules.zig.
extern const QtModuleConfig *qt_modules_config(void);
extern unsigned char *qt_fs_read(const char *path, size_t *len);
extern int qt_fs_is_file(const char *path);
extern int qt_fs_write(const char *path, const unsigned char *bytes, size_t len);
extern void qt_free(void *pointer);
extern void *qt_hash_new(void);
extern void qt_hash_update(void *state, const void *bytes, size_t len);
extern void qt_hash_final(void *state, unsigned char out[32]);
extern unsigned char *qt_cache_get(const unsigned char key[32], size_t *len);
extern void qt_cache_put(const unsigned char key[32], const unsigned char *payload, size_t len);

#define ENGINE "quickjs " QUICKJS_LOADER_VERSION

// ---- Module images ------------------------------------------------------------
//
// Format (little-endian):
//   "QTIMG\0\0\1"  u32 engine_len  engine  u32 pointer_size  u32 count
//   count x { u8 tag  u32 a_len  a  u32 b_len  b }
//   tag 1 module: a = id, b = module bytecode
//   tag 2 cjs:    a = id, b = CommonJS wrapper bytecode
//   tag 3 edge:   a = importer "\0" specifier, b = resolved id
// Bytecode is read with JS_READ_OBJ_ROM_DATA, so the image must stay mapped.

enum { TAG_MODULE = 1, TAG_CJS = 2, TAG_EDGE = 3 };
static const char image_magic[8] = { 'Q', 'T', 'I', 'M', 'G', 0, 0, 1 };

typedef struct { const char *key; size_t key_len; const uint8_t *value; size_t value_len; } Slot;
typedef struct { Slot *slots; size_t cap; size_t used; } Table;

static uint64_t hash_bytes(const char *bytes, size_t len) {
    uint64_t h = 1469598103934665603ull; // FNV-1a
    for (size_t i = 0; i < len; i++) { h ^= (unsigned char)bytes[i]; h *= 1099511628211ull; }
    return h;
}
static int table_put(Table *t, const char *key, size_t key_len, const uint8_t *value, size_t value_len) {
    if ((t->used + 1) * 2 > t->cap) {
        size_t cap = t->cap ? t->cap * 2 : 256;
        Slot *slots = calloc(cap, sizeof(Slot));
        if (!slots) return -1;
        for (size_t i = 0; i < t->cap; i++) if (t->slots[i].key) {
            size_t j = hash_bytes(t->slots[i].key, t->slots[i].key_len) & (cap - 1);
            while (slots[j].key) j = (j + 1) & (cap - 1);
            slots[j] = t->slots[i];
        }
        free(t->slots); t->slots = slots; t->cap = cap;
    }
    size_t j = hash_bytes(key, key_len) & (t->cap - 1);
    while (t->slots[j].key) {
        if (t->slots[j].key_len == key_len && !memcmp(t->slots[j].key, key, key_len)) { t->slots[j].value = value; t->slots[j].value_len = value_len; return 0; }
        j = (j + 1) & (t->cap - 1);
    }
    t->slots[j] = (Slot){ key, key_len, value, value_len };
    t->used++;
    return 0;
}
static const Slot *table_get(const Table *t, const char *key, size_t key_len) {
    if (!t->cap) return NULL;
    size_t j = hash_bytes(key, key_len) & (t->cap - 1);
    while (t->slots[j].key) {
        if (t->slots[j].key_len == key_len && !memcmp(t->slots[j].key, key, key_len)) return &t->slots[j];
        j = (j + 1) & (t->cap - 1);
    }
    return NULL;
}

typedef struct { Table modules, cjs, edges; int loaded; const char *error; } Image;
static Image image; // parsed once; the bytes are immutable and live for the process

static int read_u32(const uint8_t **p, const uint8_t *end, uint32_t *out) {
    if (end - *p < 4) return -1;
    *out = (uint32_t)(*p)[0] | (uint32_t)(*p)[1] << 8 | (uint32_t)(*p)[2] << 16 | (uint32_t)(*p)[3] << 24;
    *p += 4;
    return 0;
}
static const Image *image_get(void) {
    const QtModuleConfig *config = qt_modules_config();
    if (!config->image) return NULL;
    if (image.loaded) return image.error ? NULL : &image;
    image.loaded = 1;
    const uint8_t *p = config->image, *end = config->image + config->image_len;
    uint32_t engine_len, word, count;
    if (end - p < 8 || memcmp(p, image_magic, 8)) { image.error = "bad magic"; return NULL; }
    p += 8;
    if (read_u32(&p, end, &engine_len) || (size_t)(end - p) < engine_len) { image.error = "truncated"; return NULL; }
    if (engine_len != strlen(ENGINE) || memcmp(p, ENGINE, engine_len)) { image.error = "built for a different QuickJS"; return NULL; }
    p += engine_len;
    if (read_u32(&p, end, &word) || word != sizeof(void *)) { image.error = "built for a different pointer size"; return NULL; }
    if (read_u32(&p, end, &count)) { image.error = "truncated"; return NULL; }
    for (uint32_t i = 0; i < count; i++) {
        if (p >= end) { image.error = "truncated"; return NULL; }
        uint8_t tag = *p++;
        uint32_t a_len, b_len;
        if (read_u32(&p, end, &a_len) || (size_t)(end - p) < a_len) { image.error = "truncated"; return NULL; }
        const char *a = (const char *)p; p += a_len;
        if (read_u32(&p, end, &b_len) || (size_t)(end - p) < b_len) { image.error = "truncated"; return NULL; }
        const uint8_t *b = p; p += b_len;
        Table *t = tag == TAG_MODULE ? &image.modules : tag == TAG_CJS ? &image.cjs : tag == TAG_EDGE ? &image.edges : NULL;
        if (!t) { image.error = "unknown entry"; return NULL; }
        if (table_put(t, a, a_len, b, b_len) < 0) { image.error = "out of memory"; return NULL; }
    }
    return &image;
}

// Resolution from the image: a recorded edge, or an id that is already canonical.
static const char *image_resolve(const Image *img, const char *base, const char *name, size_t *len) {
    size_t base_len = strlen(base), name_len = strlen(name);
    char stack_key[1024], *key = base_len + name_len + 1 <= sizeof(stack_key) ? stack_key : malloc(base_len + name_len + 1);
    if (!key) return NULL;
    memcpy(key, base, base_len); key[base_len] = 0; memcpy(key + base_len + 1, name, name_len);
    const Slot *edge = table_get(&img->edges, key, base_len + name_len + 1);
    if (key != stack_key) free(key);
    if (edge) { *len = edge->value_len; return (const char *)edge->value; }
    if (table_get(&img->modules, name, name_len) || table_get(&img->cjs, name, name_len)) { *len = name_len; return name; }
    return NULL;
}

// ---- Recording (quicktui_build_image) ----------------------------------------------

typedef struct { uint8_t tag; char *a; size_t a_len; uint8_t *b; size_t b_len; } Record;
typedef struct { Record *items; size_t count, cap; Table seen; Table read_set; char **reads; size_t read_count, read_cap; } Recorder;

// Build mode: remember every file the policy read, for the depfile.
static void record_read(Recorder *r, const char *path) {
    size_t len = strlen(path);
    if (table_get(&r->read_set, path, len)) return;
    if (r->read_count == r->read_cap) {
        size_t cap = r->read_cap ? r->read_cap * 2 : 256;
        char **reads = realloc(r->reads, cap * sizeof(char *));
        if (!reads) return;
        r->reads = reads; r->read_cap = cap;
    }
    char *copy = malloc(len + 1);
    if (!copy) return;
    memcpy(copy, path, len + 1);
    r->reads[r->read_count++] = copy;
    table_put(&r->read_set, copy, len, NULL, 0);
}

static int record_add(Recorder *r, uint8_t tag, const char *a, size_t a_len, const uint8_t *b, size_t b_len) {
    // Dedup key: tag byte + a.
    char *key = malloc(a_len + 1);
    if (!key) return -1;
    key[0] = (char)tag; memcpy(key + 1, a, a_len);
    if (table_get(&r->seen, key, a_len + 1)) { free(key); return 0; }
    if (r->count == r->cap) {
        size_t cap = r->cap ? r->cap * 2 : 256;
        Record *items = realloc(r->items, cap * sizeof(Record));
        if (!items) { free(key); return -1; }
        r->items = items; r->cap = cap;
    }
    Record *rec = &r->items[r->count];
    rec->tag = tag;
    rec->a = malloc(a_len ? a_len : 1); rec->b = malloc(b_len ? b_len : 1);
    if (!rec->a || !rec->b) { free(rec->a); free(rec->b); free(key); return -1; }
    memcpy(rec->a, a, a_len); rec->a_len = a_len; memcpy(rec->b, b, b_len); rec->b_len = b_len;
    r->count++;
    return table_put(&r->seen, key, a_len + 1, NULL, 0); // key is owned by the table
}
static int record_has(Recorder *r, uint8_t tag, const char *a) {
    size_t a_len = strlen(a);
    char stack_key[1024], *key = a_len + 1 <= sizeof(stack_key) ? stack_key : malloc(a_len + 1);
    if (!key) return 0;
    key[0] = (char)tag; memcpy(key + 1, a, a_len);
    int found = table_get(&r->seen, key, a_len + 1) != NULL;
    if (key != stack_key) free(key);
    return found;
}
static void recorder_free(Recorder *r) {
    for (size_t i = 0; i < r->count; i++) { free(r->items[i].a); free(r->items[i].b); }
    for (size_t i = 0; i < r->seen.cap; i++) free((char *)r->seen.slots[i].key);
    for (size_t i = 0; i < r->read_count; i++) free(r->reads[i]);
    free(r->items); free(r->seen.slots); free(r->reads); free(r->read_set.slots);
    memset(r, 0, sizeof(*r));
}

// ---- Loader state --------------------------------------------------------------------

typedef struct {
    JSContext *realm;           // loader realm, NULL in image-only mode
    JSValue resolve, format, key, build, requires; // policy functions, owned by realm
    unsigned char salt[32];
    int trace;
    unsigned hits, misses, uncached, from_image;
    QtCompileHook *hook;
    const Image *image;
    Recorder *recorder;
} Loader;

int qt_modules_enabled(void) { return qt_modules_config()->active; }

static void note_read(JSContext *realm, const char *path, int found) {
    Loader *loader = JS_GetRuntimeOpaque(JS_GetRuntime(realm));
    if (found && loader && loader->recorder) record_read(loader->recorder, path);
}

static Loader *loader_of(JSContext *ctx) {
    return JS_GetRuntimeOpaque(JS_GetRuntime(ctx));
}

// ---- Loader realm host functions ---------------------------------------------

static void note_read(JSContext *realm, const char *path, int found);
static JSValue host_read(JSContext *realm, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self; (void)argc;
    const char *path = JS_ToCString(realm, argv[0]);
    if (!path) return JS_EXCEPTION;
    size_t len = 0; unsigned char *bytes = qt_fs_read(path, &len);
    note_read(realm, path, bytes != NULL);
    JS_FreeCString(realm, path);
    if (!bytes) return JS_UNDEFINED;
    JSValue text = JS_NewStringLen(realm, (const char *)bytes, len);
    qt_free(bytes);
    return text;
}

static JSValue host_read_base64(JSContext *realm, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self; (void)argc;
    static const char digits[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const char *path = JS_ToCString(realm, argv[0]);
    if (!path) return JS_EXCEPTION;
    size_t len = 0; unsigned char *bytes = qt_fs_read(path, &len);
    note_read(realm, path, bytes != NULL);
    JS_FreeCString(realm, path);
    if (!bytes) return JS_UNDEFINED;
    size_t out_len = (len + 2) / 3 * 4;
    char *out = malloc(out_len + 1);
    if (!out) { qt_free(bytes); return JS_ThrowOutOfMemory(realm); }
    size_t o = 0;
    for (size_t i = 0; i < len; i += 3) {
        uint32_t v = (uint32_t)bytes[i] << 16 | (i + 1 < len ? (uint32_t)bytes[i + 1] << 8 : 0) | (i + 2 < len ? bytes[i + 2] : 0);
        out[o++] = digits[v >> 18 & 63]; out[o++] = digits[v >> 12 & 63];
        out[o++] = i + 1 < len ? digits[v >> 6 & 63] : '=';
        out[o++] = i + 2 < len ? digits[v & 63] : '=';
    }
    qt_free(bytes);
    JSValue text = JS_NewStringLen(realm, out, o);
    free(out);
    return text;
}

static JSValue host_is_file(JSContext *realm, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self; (void)argc;
    const char *path = JS_ToCString(realm, argv[0]);
    if (!path) return JS_EXCEPTION;
    int ok = qt_fs_is_file(path);
    JS_FreeCString(realm, path);
    return JS_NewBool(realm, ok);
}

// Move the loader realm's pending exception into ctx as an Error.
static void forward_exception(JSContext *ctx, JSContext *realm, const char *what, const char *name) {
    JSValue error = JS_GetException(realm);
    const char *message = JS_ToCString(realm, error);
    JS_ThrowReferenceError(ctx, "%s %s: %s", what, name, message ? message : "unknown error");
    JS_FreeCString(realm, message);
    JS_FreeValue(realm, error);
}

// Sucrase's recursive-descent parser needs more than QuickJS's default 1 MiB
// in unoptimized builds. The runtime's limit is raised only while the loader
// realm runs; QuickTUI otherwise uses the default (it never sets its own).
#define QT_LOADER_STACK_SIZE (4u * 1024 * 1024)

// Call a policy function with string arguments; returns a C string owned by
// the realm (free with JS_FreeCString(realm, ...)), NULL with *is_null set
// for a null result, or NULL with an exception forwarded into ctx.
static const char *call_policy(JSContext *ctx, Loader *loader, JSValueConst fn, const char *a, const char *b, size_t *len, int *is_null, const char *what) {
    JSContext *realm = loader->realm;
    if (is_null) *is_null = 0;
    if (!realm) { JS_ThrowReferenceError(ctx, "%s %s: not in the module image", what, a); return NULL; }
    JSRuntime *rt = JS_GetRuntime(realm);
    JSValue args[2] = { JS_NewString(realm, a), JS_NewString(realm, b) };
    JS_SetMaxStackSize(rt, QT_LOADER_STACK_SIZE);
    JSValue result = JS_Call(realm, fn, JS_UNDEFINED, 2, args);
    JS_SetMaxStackSize(rt, JS_DEFAULT_STACK_SIZE);
    JS_FreeValue(realm, args[0]); JS_FreeValue(realm, args[1]);
    if (JS_IsException(result)) { forward_exception(ctx, realm, what, a); return NULL; }
    if (JS_IsNull(result) && is_null) { *is_null = 1; return NULL; }
    const char *text = JS_ToCStringLen(realm, len, result);
    JS_FreeValue(realm, result);
    if (!text) forward_exception(ctx, realm, what, a);
    return text;
}

// ---- Compilation: image, then bytecode cache, then build ---------------------------

static void record_value(JSContext *ctx, Loader *loader, uint8_t tag, const char *id, JSValueConst value) {
    if (!loader->recorder) return;
    size_t size = 0; uint8_t *bytecode = JS_WriteObject(ctx, &size, value, JS_WRITE_OBJ_BYTECODE);
    if (!bytecode) { JS_FreeValue(ctx, JS_GetException(ctx)); return; }
    record_add(loader->recorder, tag, id, strlen(id), bytecode, size);
    js_free(ctx, bytecode);
}

static JSValue obtain_uncounted(JSContext *ctx, Loader *loader, const char *id, const char *mode, int eval_type);
// Compile module `id` for `mode` ("module" or "cjs") in ctx, compile-only.
static JSValue obtain(JSContext *ctx, Loader *loader, const char *id, const char *mode, int eval_type) {
    if (loader->image) {
        const Slot *slot = table_get(mode[0] == 'm' ? &loader->image->modules : &loader->image->cjs, id, strlen(id));
        if (slot) {
            loader->from_image++;
            return JS_ReadObject(ctx, slot->value, slot->value_len, JS_READ_OBJ_BYTECODE | JS_READ_OBJ_ROM_DATA);
        }
    }
    if (loader->hook) loader->hook(ctx, 1);
    JSValue value = obtain_uncounted(ctx, loader, id, mode, eval_type);
    if (loader->hook) loader->hook(ctx, 0);
    if (!JS_IsException(value)) record_value(ctx, loader, mode[0] == 'm' ? TAG_MODULE : TAG_CJS, id, value);
    return value;
}

static JSValue obtain_uncounted(JSContext *ctx, Loader *loader, const char *id, const char *mode, int eval_type) {
    JSContext *realm = loader->realm;
    size_t key_len = 0; int no_cache = 0;
    const char *key_text = call_policy(ctx, loader, loader->key, id, mode, &key_len, &no_cache, "Cannot load");
    if (!key_text && !no_cache) return JS_EXCEPTION;
    unsigned char key[32];
    int cacheable = key_text != NULL;
    if (cacheable) {
        void *hash = qt_hash_new();
        if (!hash) { JS_FreeCString(realm, key_text); return JS_ThrowOutOfMemory(ctx); }
        qt_hash_update(hash, loader->salt, sizeof(loader->salt));
        qt_hash_update(hash, mode, strlen(mode));
        qt_hash_update(hash, id, strlen(id));
        qt_hash_update(hash, key_text, key_len);
        qt_hash_final(hash, key);
        JS_FreeCString(realm, key_text);
        size_t len = 0; unsigned char *bytes = qt_cache_get(key, &len);
        if (bytes) {
            JSValue value = JS_ReadObject(ctx, bytes, len, JS_READ_OBJ_BYTECODE);
            qt_free(bytes);
            if (!JS_IsException(value)) { loader->hits++; if (loader->trace) fprintf(stderr, "[modules] hit  %s %s\n", mode, id); return value; }
            JS_FreeValue(ctx, JS_GetException(ctx)); // stale entry: rebuild
        }
    }
    size_t code_len = 0;
    const char *code = call_policy(ctx, loader, loader->build, id, mode, &code_len, NULL, "Cannot build");
    if (!code) return JS_EXCEPTION;
    JSValue value = JS_Eval(ctx, code, code_len, id, eval_type | JS_EVAL_FLAG_COMPILE_ONLY);
    JS_FreeCString(realm, code);
    if (JS_IsException(value)) return value;
    if (cacheable) {
        size_t size = 0; uint8_t *bytecode = JS_WriteObject(ctx, &size, value, JS_WRITE_OBJ_BYTECODE);
        if (bytecode) { qt_cache_put(key, bytecode, size); js_free(ctx, bytecode); }
        else JS_FreeValue(ctx, JS_GetException(ctx));
        loader->misses++;
        if (loader->trace) fprintf(stderr, "[modules] miss %s %s\n", mode, id);
    } else {
        loader->uncached++;
        if (loader->trace) fprintf(stderr, "[modules] gen  %s %s\n", mode, id);
    }
    return value;
}

// Resolve `name` imported from `base`; returns js_malloc'd storage in ctx.
static char *resolve_to(JSContext *ctx, Loader *loader, const char *base, const char *name, size_t *out_len) {
    size_t len = 0;
    if (loader->image) {
        const char *hit = image_resolve(loader->image, base, name, &len);
        if (hit) {
            char *copy = js_malloc(ctx, len + 1);
            if (copy) { memcpy(copy, hit, len); copy[len] = 0; if (out_len) *out_len = len; }
            return copy;
        }
    }
    const char *resolved = call_policy(ctx, loader, loader->resolve, name, base, &len, NULL, "Cannot resolve");
    if (!resolved) return NULL;
    char *copy = js_malloc(ctx, len + 1);
    if (copy) { memcpy(copy, resolved, len); copy[len] = 0; if (out_len) *out_len = len; }
    JS_FreeCString(loader->realm, resolved);
    if (copy && loader->recorder) {
        size_t base_len = strlen(base), name_len = strlen(name);
        char *edge = malloc(base_len + name_len + 1);
        if (edge) {
            memcpy(edge, base, base_len); edge[base_len] = 0; memcpy(edge + base_len + 1, name, name_len);
            record_add(loader->recorder, TAG_EDGE, edge, base_len + name_len + 1, (const uint8_t *)copy, len);
            free(edge);
        }
    }
    return copy;
}

static char *normalize(JSContext *ctx, const char *base, const char *name, void *opaque) {
    return resolve_to(ctx, opaque, base, name, NULL);
}

static JSModuleDef *load_module(JSContext *ctx, const char *name, void *opaque, JSValueConst attributes) {
    (void)attributes; // The policy classifies by extension (.md is text, .json is JSON).
    JSValue value = obtain(ctx, opaque, name, "module", JS_EVAL_TYPE_MODULE);
    if (JS_IsException(value)) return NULL;
    JSModuleDef *m = JS_VALUE_GET_PTR(value);
    JS_FreeValue(ctx, value); // the module list keeps it alive
    return m;
}

// ---- Application realm CommonJS host --------------------------------------------

static JSValue app_resolve(JSContext *ctx, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self; (void)argc;
    const char *spec = JS_ToCString(ctx, argv[0]), *from = JS_ToCString(ctx, argv[1]);
    JSValue result = JS_EXCEPTION;
    if (spec && from) {
        size_t len = 0;
        char *resolved = resolve_to(ctx, loader_of(ctx), from, spec, &len);
        if (resolved) { result = JS_NewStringLen(ctx, resolved, len); js_free(ctx, resolved); }
    }
    JS_FreeCString(ctx, spec); JS_FreeCString(ctx, from);
    return result;
}

static JSValue app_format(JSContext *ctx, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self; (void)argc;
    Loader *loader = loader_of(ctx);
    const char *id = JS_ToCString(ctx, argv[0]);
    if (!id) return JS_EXCEPTION;
    if (loader->image) {
        size_t id_len = strlen(id);
        const char *known = table_get(&loader->image->cjs, id, id_len) ? "cjs" : table_get(&loader->image->modules, id, id_len) ? "esm" : NULL;
        if (known) { JS_FreeCString(ctx, id); return JS_NewString(ctx, known); }
    }
    size_t len = 0;
    const char *format = call_policy(ctx, loader, loader->format, id, "", &len, NULL, "Cannot load");
    JS_FreeCString(ctx, id);
    if (!format) return JS_EXCEPTION;
    JSValue result = JS_NewStringLen(ctx, format, len);
    JS_FreeCString(loader->realm, format);
    return result;
}

// Evaluate a one-line ES module (`import * as ns from id; export { ns }`) now
// and return its `ns` export: synchronous require() of an ES module graph.
static JSValue app_import_sync(JSContext *ctx, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self; (void)argc;
    size_t len = 0;
    const char *source = JS_ToCStringLen(ctx, &len, argv[0]);
    const char *name = JS_ToCString(ctx, argv[1]);
    JSValue result = JS_EXCEPTION;
    if (!source || !name) goto done;
    JSValue func = JS_Eval(ctx, source, len, name, JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
    if (JS_IsException(func)) goto done;
    JSModuleDef *m = JS_VALUE_GET_PTR(func);
    JSValue promise = JS_EvalFunction(ctx, func);
    if (JS_IsException(promise)) goto done;
    JSRuntime *rt = JS_GetRuntime(ctx);
    for (int jobs = 0; JS_PromiseState(ctx, promise) == JS_PROMISE_PENDING && JS_IsJobPending(rt) && jobs < 1000000; jobs++) {
        JSContext *job_ctx = NULL;
        if (JS_ExecutePendingJob(rt, &job_ctx) < 0) break;
    }
    int state = JS_PromiseState(ctx, promise);
    if (state == JS_PROMISE_REJECTED) JS_Throw(ctx, JS_PromiseResult(ctx, promise)); // PromiseResult returns a new reference
    else if (state == JS_PROMISE_PENDING) JS_ThrowInternalError(ctx, "require() of %s did not settle (top-level await?)", name);
    else {
        JSValue namespace = JS_GetModuleNamespace(ctx, m);
        if (!JS_IsException(namespace)) { result = JS_GetPropertyStr(ctx, namespace, "ns"); JS_FreeValue(ctx, namespace); }
    }
    JS_FreeValue(ctx, promise);
done:
    JS_FreeCString(ctx, source); JS_FreeCString(ctx, name);
    return result;
}

static JSValue app_compile(JSContext *ctx, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self; (void)argc;
    const char *id = JS_ToCString(ctx, argv[0]);
    if (!id) return JS_EXCEPTION;
    JSValue script = obtain(ctx, loader_of(ctx), id, "cjs", JS_EVAL_TYPE_GLOBAL);
    JS_FreeCString(ctx, id);
    if (JS_IsException(script)) return script;
    return JS_EvalFunction(ctx, script); // completion value: the wrapper function
}

// ---- Setup and teardown ------------------------------------------------------------

static int eval_into(JSContext *realm, const char *source, size_t len, const char *name) {
    JSValue result = JS_Eval(realm, source, len, name, JS_EVAL_TYPE_GLOBAL);
    if (JS_IsException(result)) return -1;
    JS_FreeValue(realm, result);
    return 0;
}

static void report(JSContext *realm, JSContext *ctx) {
    JSValue error = JS_GetException(realm);
    const char *message = JS_ToCString(realm, error);
    JS_ThrowInternalError(ctx, "module loader setup failed: %s", message ? message : "unknown error");
    JS_FreeCString(realm, message); JS_FreeValue(realm, error);
}

static int install_realm(JSContext *ctx, Loader *loader) {
    const QtModuleConfig *config = qt_modules_config();
    JSContext *realm = loader->realm = JS_NewContext(JS_GetRuntime(ctx));
    if (!realm) { JS_ThrowOutOfMemory(ctx); return -1; }
    JSValue global = JS_GetGlobalObject(realm);
    JSValue host = JS_NewObject(realm);
    JS_SetPropertyStr(realm, host, "read", JS_NewCFunction(realm, host_read, "read", 1));
    JS_SetPropertyStr(realm, host, "readBase64", JS_NewCFunction(realm, host_read_base64, "readBase64", 1));
    JS_SetPropertyStr(realm, host, "isFile", JS_NewCFunction(realm, host_is_file, "isFile", 1));
    JS_SetPropertyStr(realm, global, "__loaderHost", host);
    JSValue settings = JS_NewObject(realm);
    JS_SetPropertyStr(realm, settings, "root", JS_NewString(realm, config->root));
    JS_SetPropertyStr(realm, settings, "entry", JS_NewString(realm, config->entry));
    JS_SetPropertyStr(realm, settings, "demoAssets", JS_NewBool(realm, config->demo_assets));
    JS_SetPropertyStr(realm, settings, "hosted", JS_NewBool(realm, config->hosted));
    JS_SetPropertyStr(realm, global, "__loaderConfig", settings);
    int failed = eval_into(realm, config->sucrase, config->sucrase_len, "vendor/sucrase/sucrase.js") < 0
        || eval_into(realm, config->commonjs, config->commonjs_len, "js/loader/cjs.js") < 0
        || eval_into(realm, config->policy, config->policy_len, "js/loader/policy.js") < 0;
    if (!failed) {
        JSValue policy = JS_GetPropertyStr(realm, global, "__loaderPolicy");
        loader->resolve = JS_GetPropertyStr(realm, policy, "resolve");
        loader->format = JS_GetPropertyStr(realm, policy, "format");
        loader->key = JS_GetPropertyStr(realm, policy, "key");
        loader->build = JS_GetPropertyStr(realm, policy, "build");
        loader->requires = JS_GetPropertyStr(realm, policy, "requires");
        JS_FreeValue(realm, policy);
        failed = !JS_IsFunction(realm, loader->resolve) || !JS_IsFunction(realm, loader->format) || !JS_IsFunction(realm, loader->key)
            || !JS_IsFunction(realm, loader->build) || !JS_IsFunction(realm, loader->requires);
        if (failed) JS_ThrowTypeError(realm, "js/loader/policy.js did not define __loaderPolicy");
    }
    JS_FreeValue(realm, global);
    if (failed) { report(realm, ctx); return -1; }

    // Cache salt: everything that changes compiled output besides the source.
    void *hash = qt_hash_new();
    if (!hash) { JS_ThrowOutOfMemory(ctx); return -1; }
    const size_t word = sizeof(void *);
    qt_hash_update(hash, ENGINE, strlen(ENGINE));
    qt_hash_update(hash, &word, sizeof(word));
    // Image builds strip function source (JS_STRIP_SOURCE); keep their cache entries apart.
    const char *strip = config->record ? "strip-source" : "full";
    qt_hash_update(hash, strip, strlen(strip));
    qt_hash_update(hash, config->sucrase, config->sucrase_len);
    qt_hash_update(hash, config->commonjs, config->commonjs_len);
    qt_hash_update(hash, config->policy, config->policy_len);
    qt_hash_final(hash, loader->salt);
    return 0;
}

int qt_modules_install(JSContext *ctx, QtCompileHook *hook) {
    const QtModuleConfig *config = qt_modules_config();
    JSRuntime *rt = JS_GetRuntime(ctx);
    Loader *loader = calloc(1, sizeof(*loader));
    if (!loader) { JS_ThrowOutOfMemory(ctx); return -1; }
    loader->trace = config->trace;
    loader->hook = hook;
    loader->resolve = loader->format = loader->key = loader->build = loader->requires = JS_UNDEFINED;
    JS_SetRuntimeOpaque(rt, loader);
    if (config->image) {
        loader->image = image_get();
        if (!loader->image) { JS_ThrowInternalError(ctx, "module image rejected: %s", image.error ? image.error : "unknown error"); return -1; }
    }
    if (config->root && config->root[0] && install_realm(ctx, loader) < 0) return -1;
    if (!loader->image && !loader->realm) { JS_ThrowInternalError(ctx, "source mode needs a checkout or a module image"); return -1; }

    JS_SetModuleLoaderFunc2(rt, normalize, load_module, NULL, loader);

    // CommonJS runtime in the application realm.
    JSValue app_global = JS_GetGlobalObject(ctx);
    JSValue app_host = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, app_host, "resolve", JS_NewCFunction(ctx, app_resolve, "resolve", 2));
    JS_SetPropertyStr(ctx, app_host, "format", JS_NewCFunction(ctx, app_format, "format", 1));
    JS_SetPropertyStr(ctx, app_host, "compile", JS_NewCFunction(ctx, app_compile, "compile", 1));
    JS_SetPropertyStr(ctx, app_host, "importSync", JS_NewCFunction(ctx, app_import_sync, "importSync", 2));
    JS_DefinePropertyValueStr(ctx, app_global, "__quicktuiLoaderHost", app_host, JS_PROP_CONFIGURABLE);
    JS_FreeValue(ctx, app_global);
    if (eval_into(ctx, config->commonjs, config->commonjs_len, "js/loader/cjs.js") < 0) return -1;
    static const char install[] =
        "{const cjs=__quicktuiCreateCommonJs(__quicktuiLoaderHost);"
        "Object.defineProperty(globalThis,'__quicktuiRequire',{value:cjs.load,configurable:true});"
        "Object.defineProperty(globalThis,'__quicktuiRequireFrom',{value:cjs.requireFrom,configurable:true});}";
    return eval_into(ctx, install, sizeof(install) - 1, "<quicktui-loader>");
}

static const char entry_source[] = "import \"quicktui:entry\";\n";

static void trace_counts(Loader *loader) {
    if (loader && loader->trace)
        fprintf(stderr, "[modules] image=%u cache hits=%u misses=%u uncached=%u\n", loader->from_image, loader->hits, loader->misses, loader->uncached);
}

// Evaluate the entry graph. Settles top-level await before returning so the
// host sees the same globals it would after evaluating the bundle.
int qt_modules_run_entry(JSContext *ctx) {
    JSValue promise = JS_Eval(ctx, entry_source, sizeof(entry_source) - 1, "<quicktui>", JS_EVAL_TYPE_MODULE);
    if (JS_IsException(promise)) return -1;
    JSRuntime *rt = JS_GetRuntime(ctx);
    for (int jobs = 0; JS_PromiseState(ctx, promise) == JS_PROMISE_PENDING && JS_IsJobPending(rt); jobs++) {
        JSContext *job_ctx = NULL;
        if (jobs > 1000000 || JS_ExecutePendingJob(rt, &job_ctx) < 0) break;
    }
    int state = JS_PromiseState(ctx, promise);
    Loader *loader = loader_of(ctx);
    if (state == JS_PROMISE_REJECTED) {
        if (loader && loader->trace) {
            JSValue reason = JS_PromiseResult(ctx, promise);
            const char *text = JS_ToCString(ctx, reason);
            JSValue stack = JS_GetPropertyStr(ctx, reason, "stack");
            const char *trace = JS_ToCString(ctx, stack);
            fprintf(stderr, "[modules] entry failed: %s\n%s\n", text ? text : "?", trace ? trace : "");
            JS_FreeCString(ctx, text); JS_FreeCString(ctx, trace); JS_FreeValue(ctx, stack); JS_FreeValue(ctx, reason);
        }
        JS_Throw(ctx, JS_PromiseResult(ctx, promise)); // PromiseResult returns a new reference
        JS_FreeValue(ctx, promise);
        return -1;
    }
    JS_FreeValue(ctx, promise);
    trace_counts(loader);
    if (state == JS_PROMISE_PENDING) { JS_ThrowInternalError(ctx, "entry module did not settle"); return -1; }
    return 0;
}

// Call after freeing the application context, before JS_FreeRuntime.
void qt_modules_release(JSRuntime *rt) {
    Loader *loader = JS_GetRuntimeOpaque(rt);
    if (!loader) return;
    JSContext *realm = loader->realm;
    if (realm) {
        JS_FreeValue(realm, loader->resolve); JS_FreeValue(realm, loader->format); JS_FreeValue(realm, loader->key);
        JS_FreeValue(realm, loader->build); JS_FreeValue(realm, loader->requires);
        JS_FreeContext(realm);
    }
    JS_SetRuntimeOpaque(rt, NULL);
    free(loader);
}

// ---- Building an image -----------------------------------------------------------------

static void print_exception(JSContext *ctx, const char *what) {
    JSValue error = JS_GetException(ctx);
    const char *text = JS_ToCString(ctx, error);
    JSValue stack = JS_GetPropertyStr(ctx, error, "stack");
    const char *trace = JS_IsUndefined(stack) ? NULL : JS_ToCString(ctx, stack);
    fprintf(stderr, "quicktui image: %s: %s\n%s", what, text ? text : "unknown error", trace ? trace : "");
    JS_FreeCString(ctx, text); JS_FreeCString(ctx, trace); JS_FreeValue(ctx, stack); JS_FreeValue(ctx, error);
}

// Compile `source` as a module named `name` and load (not evaluate) its graph.
static int load_graph(JSContext *ctx, const char *source, size_t len, const char *name) {
    JSValue func = JS_Eval(ctx, source, len, name, JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
    if (JS_IsException(func)) return -1;
    int ok = JS_ResolveModule(ctx, func);
    JS_FreeValue(ctx, func);
    return ok < 0 ? -1 : 0;
}

// Close the recording over literal require() targets, which static imports
// do not reach (js/examples.ts selects demos with require()).
static int follow_requires(JSContext *ctx, Loader *loader) {
    Recorder *r = loader->recorder;
    for (size_t i = 0; i < r->count; i++) {
        uint8_t tag = r->items[i].tag;
        if (tag == TAG_EDGE) continue;
        char *id = malloc(r->items[i].a_len + 1);
        if (!id) return -1;
        memcpy(id, r->items[i].a, r->items[i].a_len); id[r->items[i].a_len] = 0;
        size_t len = 0;
        const char *json = call_policy(ctx, loader, loader->requires, id, tag == TAG_MODULE ? "module" : "cjs", &len, NULL, "Cannot scan");
        if (!json) { free(id); return -1; }
        JSValue list = JS_ParseJSON(ctx, json, len, "<requires>");
        JS_FreeCString(loader->realm, json);
        if (JS_IsException(list)) { free(id); return -1; }
        int64_t n = 0;
        JSValue length = JS_GetPropertyStr(ctx, list, "length");
        JS_ToInt64(ctx, &n, length); JS_FreeValue(ctx, length);
        int failed = 0;
        for (int64_t k = 0; k < n && !failed; k++) {
            JSValue item = JS_GetPropertyUint32(ctx, list, (uint32_t)k);
            JSValue v0 = JS_GetPropertyUint32(ctx, item, 0), v1 = JS_GetPropertyUint32(ctx, item, 1), v2 = JS_GetPropertyUint32(ctx, item, 2);
            const char *spec = JS_ToCString(ctx, v0), *target = JS_IsNull(v1) ? NULL : JS_ToCString(ctx, v1), *format = JS_ToCString(ctx, v2);
            if (!target) {
                fprintf(stderr, "quicktui image: skipping require(\"%s\") in %s: %s\n", spec ? spec : "?", id, format ? format : "");
            } else {
                // Record the edge, as resolve_to would at run time.
                char *resolved = resolve_to(ctx, loader, id, spec, NULL);
                if (resolved) js_free(ctx, resolved); else failed = 1;
                if (!failed && !strcmp(format, "cjs") && !record_has(r, TAG_CJS, target)) {
                    JSValue body = obtain(ctx, loader, target, "cjs", JS_EVAL_TYPE_GLOBAL);
                    if (JS_IsException(body)) failed = 1; else JS_FreeValue(ctx, body);
                } else if (!failed && strcmp(format, "cjs") && !record_has(r, TAG_MODULE, target)) {
                    // Same wrapper cjs.js evaluates for require() of an ES module.
                    size_t t_len = strlen(target);
                    char *wrapper = malloc(t_len + 64), *name = malloc(t_len + 16);
                    if (!wrapper || !name) failed = 1;
                    else {
                        JSValue quoted = JS_NewString(ctx, target);
                        JSValue json_target = JS_JSONStringify(ctx, quoted, JS_UNDEFINED, JS_UNDEFINED);
                        const char *q = JS_ToCString(ctx, json_target);
                        int w = snprintf(wrapper, t_len + 64, "import * as ns from %s;\nexport { ns };\n", q ? q : "\"\"");
                        snprintf(name, t_len + 16, "<require %s>", target);
                        failed = !q || load_graph(ctx, wrapper, (size_t)w, name) < 0;
                        JS_FreeCString(ctx, q); JS_FreeValue(ctx, json_target); JS_FreeValue(ctx, quoted);
                    }
                    free(wrapper); free(name);
                }
            }
            JS_FreeCString(ctx, spec); JS_FreeCString(ctx, target); JS_FreeCString(ctx, format);
            JS_FreeValue(ctx, v0); JS_FreeValue(ctx, v1); JS_FreeValue(ctx, v2); JS_FreeValue(ctx, item);
        }
        JS_FreeValue(ctx, list);
        if (failed) { print_exception(ctx, id); free(id); return -1; }
        free(id);
    }
    return 0;
}

static int append(uint8_t **buf, size_t *len, size_t *cap, const void *bytes, size_t n) {
    if (*len + n > *cap) {
        size_t next = *cap ? *cap * 2 : 1 << 20;
        while (next < *len + n) next *= 2;
        uint8_t *grown = realloc(*buf, next);
        if (!grown) return -1;
        *buf = grown; *cap = next;
    }
    memcpy(*buf + *len, bytes, n); *len += n;
    return 0;
}
static int append_u32(uint8_t **buf, size_t *len, size_t *cap, uint32_t v) {
    uint8_t b[4] = { v & 255, v >> 8 & 255, v >> 16 & 255, v >> 24 & 255 };
    return append(buf, len, cap, b, 4);
}

// Makefile syntax, as zig build's addDepFileOutputArg expects.
static void append_escaped(uint8_t **buf, size_t *len, size_t *cap, const char *path) {
    for (const char *p = path; *p; p++) {
        if (*p == ' ' || *p == '#' || *p == '\\') append(buf, len, cap, "\\", 1);
        if (*p == '$') append(buf, len, cap, "$", 1);
        append(buf, len, cap, p, 1);
    }
}
static int write_depfile(const char *depfile, const char *out_path, Recorder *r) {
    if (!depfile || !depfile[0]) return 0;
    uint8_t *buf = NULL; size_t len = 0, cap = 0;
    append_escaped(&buf, &len, &cap, out_path);
    append(&buf, &len, &cap, ":", 1);
    for (size_t i = 0; i < r->read_count; i++) {
        append(&buf, &len, &cap, " \\\n  ", 5);
        append_escaped(&buf, &len, &cap, r->reads[i]);
    }
    append(&buf, &len, &cap, "\n", 1);
    int failed = !buf || qt_fs_write(depfile, buf, len) != 0;
    if (failed) fprintf(stderr, "quicktui image: cannot write %s\n", depfile);
    free(buf);
    return failed;
}

// Record every module reachable from the configured entry and write an image.
// Nothing is evaluated: no application code runs at build time.
int quicktui_build_image(const char *out_path) {
    int result = 1;
    JSRuntime *rt = JS_NewRuntime();
    if (!rt) return 1;
    JS_SetMemoryLimit(rt, 1024u * 1024 * 1024);
    // Like qjsc's default: drop function source text (Function.prototype.toString
    // then returns a stub) but keep line tables for stack traces.
    JS_SetStripInfo(rt, JS_STRIP_SOURCE);
    JSContext *ctx = JS_NewContext(rt);
    if (!ctx) { JS_FreeRuntime(rt); return 1; }
    Recorder recorder = { 0 };
    if (qt_modules_install(ctx, NULL) < 0) { print_exception(ctx, "setup"); goto done; }
    Loader *loader = loader_of(ctx);
    if (!loader->realm) { fputs("quicktui image: building needs a checkout\n", stderr); goto done; }
    loader->image = NULL; // never copy from an existing image
    loader->recorder = &recorder;
    if (load_graph(ctx, entry_source, sizeof(entry_source) - 1, "<quicktui>") < 0) { print_exception(ctx, "entry"); goto done; }
    if (follow_requires(ctx, loader) < 0) goto done;

    uint8_t *buf = NULL; size_t len = 0, cap = 0;
    unsigned counts[4] = { 0 };
    size_t bytecode = 0;
    int bad = append(&buf, &len, &cap, image_magic, 8)
        || append_u32(&buf, &len, &cap, (uint32_t)strlen(ENGINE)) || append(&buf, &len, &cap, ENGINE, strlen(ENGINE))
        || append_u32(&buf, &len, &cap, (uint32_t)sizeof(void *)) || append_u32(&buf, &len, &cap, (uint32_t)recorder.count);
    for (size_t i = 0; i < recorder.count && !bad; i++) {
        Record *rec = &recorder.items[i];
        counts[rec->tag]++;
        if (rec->tag != TAG_EDGE) bytecode += rec->b_len;
        bad = append(&buf, &len, &cap, &rec->tag, 1)
            || append_u32(&buf, &len, &cap, (uint32_t)rec->a_len) || append(&buf, &len, &cap, rec->a, rec->a_len)
            || append_u32(&buf, &len, &cap, (uint32_t)rec->b_len) || append(&buf, &len, &cap, rec->b, rec->b_len);
    }
    if (bad || qt_fs_write(out_path, buf, len) != 0) fprintf(stderr, "quicktui image: cannot write %s\n", out_path);
    else {
        if (!qt_modules_config()->quiet) fprintf(stderr, "quicktui image: %s: %u modules, %u CommonJS bodies, %u edges, %zu bytes of bytecode, %zu bytes total\n",
                out_path, counts[TAG_MODULE], counts[TAG_CJS], counts[TAG_EDGE], bytecode, len);
        result = write_depfile(qt_modules_config()->depfile, out_path, &recorder);
    }
    free(buf);
done:
    if (loader_of(ctx)) loader_of(ctx)->recorder = NULL;
    JS_FreeContext(ctx);
    qt_modules_release(rt);
    JS_FreeRuntime(rt);
    recorder_free(&recorder);
    return result;
}
