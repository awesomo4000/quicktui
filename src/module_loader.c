// Source-module mode: QuickJS module loader glue.
//
// A second JSContext in the application's runtime (the "loader realm") holds
// Sucrase and js/loader/policy.js. QuickJS's module hooks ask that realm to
// resolve specifiers and to produce module source; the result is compiled in
// the application realm and cached as bytecode by src/modules.zig. CommonJS
// packages are executed by js/loader/cjs.js in the application realm, behind
// ES module facades whose export names the loader realm discovers.
// Only strings cross between the two realms.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "quickjs.h"
#include "module_loader.h"

typedef struct {
    int active;
    const char *root;
    const char *entry;
    int demo_assets;
    int hosted;
    const char *sucrase; size_t sucrase_len;
    const char *policy; size_t policy_len;
    const char *commonjs; size_t commonjs_len;
    const char *cache_dir;
    int trace;
} QtModuleConfig;

// Implemented in src/modules.zig.
extern const QtModuleConfig *qt_modules_config(void);
extern unsigned char *qt_fs_read(const char *path, size_t *len);
extern int qt_fs_is_file(const char *path);
extern void qt_free(void *pointer);
extern void *qt_hash_new(void);
extern void qt_hash_update(void *state, const void *bytes, size_t len);
extern void qt_hash_final(void *state, unsigned char out[32]);
extern unsigned char *qt_cache_get(const unsigned char key[32], size_t *len);
extern void qt_cache_put(const unsigned char key[32], const unsigned char *payload, size_t len);

typedef struct {
    JSContext *realm;           // loader realm
    JSValue resolve, format, key, build; // policy functions, owned by realm
    unsigned char salt[32];
    int trace;
    unsigned hits, misses, uncached;
    QtCompileHook *hook;
} Loader;

int qt_modules_enabled(void) { return qt_modules_config()->active; }

static Loader *loader_of(JSContext *ctx) {
    return JS_GetRuntimeOpaque(JS_GetRuntime(ctx));
}

// ---- Loader realm host functions ---------------------------------------------

static JSValue host_read(JSContext *realm, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self; (void)argc;
    const char *path = JS_ToCString(realm, argv[0]);
    if (!path) return JS_EXCEPTION;
    size_t len = 0; unsigned char *bytes = qt_fs_read(path, &len);
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

// Call a policy function with string arguments; returns a C string owned by
// the realm (free with JS_FreeCString(realm, ...)), NULL with *is_null set
// for a null result, or NULL with an exception forwarded into ctx.
// Sucrase's recursive-descent parser needs more than QuickJS's default 1 MiB
// in unoptimized builds. The runtime's limit is raised only while the loader
// realm runs; QuickTUI otherwise uses the default (it never sets its own).
#define QT_LOADER_STACK_SIZE (4u * 1024 * 1024)

static const char *call_policy(JSContext *ctx, Loader *loader, JSValueConst fn, const char *a, const char *b, size_t *len, int *is_null, const char *what) {
    JSContext *realm = loader->realm;
    JSRuntime *rt = JS_GetRuntime(realm);
    JSValue args[2] = { JS_NewString(realm, a), JS_NewString(realm, b) };
    JS_SetMaxStackSize(rt, QT_LOADER_STACK_SIZE);
    JSValue result = JS_Call(realm, fn, JS_UNDEFINED, 2, args);
    JS_SetMaxStackSize(rt, JS_DEFAULT_STACK_SIZE);
    JS_FreeValue(realm, args[0]); JS_FreeValue(realm, args[1]);
    if (is_null) *is_null = 0;
    if (JS_IsException(result)) { forward_exception(ctx, realm, what, a); return NULL; }
    if (JS_IsNull(result) && is_null) { *is_null = 1; return NULL; }
    const char *text = JS_ToCStringLen(realm, len, result);
    JS_FreeValue(realm, result);
    if (!text) forward_exception(ctx, realm, what, a);
    return text;
}

// ---- Compilation with the bytecode cache ---------------------------------------

static JSValue obtain_uncounted(JSContext *ctx, Loader *loader, const char *id, const char *mode, int eval_type);
// Compile module `id` for `mode` ("module" or "cjs") in ctx, compile-only.
static JSValue obtain(JSContext *ctx, Loader *loader, const char *id, const char *mode, int eval_type) {
    if (loader->hook) loader->hook(ctx, 1);
    JSValue value = obtain_uncounted(ctx, loader, id, mode, eval_type);
    if (loader->hook) loader->hook(ctx, 0);
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

static char *normalize(JSContext *ctx, const char *base, const char *name, void *opaque) {
    Loader *loader = opaque;
    size_t len = 0;
    const char *resolved = call_policy(ctx, loader, loader->resolve, name, base, &len, NULL, "Cannot resolve");
    if (!resolved) return NULL;
    char *copy = js_malloc(ctx, len + 1);
    if (copy) { memcpy(copy, resolved, len); copy[len] = 0; }
    JS_FreeCString(loader->realm, resolved);
    return copy;
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
    Loader *loader = loader_of(ctx);
    const char *spec = JS_ToCString(ctx, argv[0]), *from = JS_ToCString(ctx, argv[1]);
    JSValue result = JS_EXCEPTION;
    if (spec && from) {
        size_t len = 0;
        const char *resolved = call_policy(ctx, loader, loader->resolve, spec, from, &len, NULL, "Cannot resolve");
        if (resolved) { result = JS_NewStringLen(ctx, resolved, len); JS_FreeCString(loader->realm, resolved); }
    }
    JS_FreeCString(ctx, spec); JS_FreeCString(ctx, from);
    return result;
}

static JSValue app_format(JSContext *ctx, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self; (void)argc;
    Loader *loader = loader_of(ctx);
    const char *id = JS_ToCString(ctx, argv[0]);
    if (!id) return JS_EXCEPTION;
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

int qt_modules_install(JSContext *ctx, QtCompileHook *hook) {
    const QtModuleConfig *config = qt_modules_config();
    JSRuntime *rt = JS_GetRuntime(ctx);
    Loader *loader = calloc(1, sizeof(*loader));
    if (!loader) { JS_ThrowOutOfMemory(ctx); return -1; }
    loader->trace = config->trace;
    loader->hook = hook;
    loader->resolve = loader->format = loader->key = loader->build = JS_UNDEFINED;
    loader->realm = JS_NewContext(rt);
    if (!loader->realm) { free(loader); JS_ThrowOutOfMemory(ctx); return -1; }
    JS_SetRuntimeOpaque(rt, loader);
    JSContext *realm = loader->realm;

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
        JS_FreeValue(realm, policy);
        failed = !JS_IsFunction(realm, loader->resolve) || !JS_IsFunction(realm, loader->format) || !JS_IsFunction(realm, loader->key) || !JS_IsFunction(realm, loader->build);
        if (failed) JS_ThrowTypeError(realm, "js/loader/policy.js did not define __loaderPolicy");
    }
    JS_FreeValue(realm, global);
    if (failed) { report(realm, ctx); return -1; }

    // Cache salt: everything that changes compiled output besides the source.
    void *hash = qt_hash_new();
    if (!hash) { JS_ThrowOutOfMemory(ctx); return -1; }
    const char *engine = "quickjs " QUICKJS_LOADER_VERSION;
    const size_t word = sizeof(void *);
    qt_hash_update(hash, engine, strlen(engine));
    qt_hash_update(hash, &word, sizeof(word));
    qt_hash_update(hash, config->sucrase, config->sucrase_len);
    qt_hash_update(hash, config->commonjs, config->commonjs_len);
    qt_hash_update(hash, config->policy, config->policy_len);
    qt_hash_final(hash, loader->salt);

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

// Evaluate the entry graph. Settles top-level await before returning so the
// host sees the same globals it would after evaluating the bundle.
int qt_modules_run_entry(JSContext *ctx) {
    static const char entry[] = "import \"quicktui:entry\";\n";
    JSValue promise = JS_Eval(ctx, entry, sizeof(entry) - 1, "<quicktui>", JS_EVAL_TYPE_MODULE);
    if (JS_IsException(promise)) return -1;
    JSRuntime *rt = JS_GetRuntime(ctx);
    for (int jobs = 0; JS_PromiseState(ctx, promise) == JS_PROMISE_PENDING && JS_IsJobPending(rt); jobs++) {
        JSContext *job_ctx = NULL;
        if (jobs > 1000000 || JS_ExecutePendingJob(rt, &job_ctx) < 0) break;
    }
    int state = JS_PromiseState(ctx, promise);
    if (state == JS_PROMISE_REJECTED) {
        Loader *traced = loader_of(ctx);
        if (traced && traced->trace) {
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
    Loader *loader = loader_of(ctx);
    if (loader && loader->trace) fprintf(stderr, "[modules] cache hits=%u misses=%u uncached=%u\n", loader->hits, loader->misses, loader->uncached);
    if (state == JS_PROMISE_PENDING) { JS_ThrowInternalError(ctx, "entry module did not settle"); return -1; }
    return 0;
}

// Call before JS_FreeContext on the application context.
void qt_modules_release(JSRuntime *rt) {
    Loader *loader = JS_GetRuntimeOpaque(rt);
    if (!loader) return;
    JSContext *realm = loader->realm;
    JS_FreeValue(realm, loader->resolve); JS_FreeValue(realm, loader->format); JS_FreeValue(realm, loader->key); JS_FreeValue(realm, loader->build);
    JS_FreeContext(realm);
    JS_SetRuntimeOpaque(rt, NULL);
    free(loader);
}
