#include "quickjs.h"
#include <stdio.h>

extern int quicktui_native_probe(void);

typedef struct {
    int unhandled_rejections;
    int diagnostics;
} Host;

static void report_value(JSContext *ctx, JSValueConst value) {
    Host *host = JS_GetContextOpaque(ctx);
    if (!host->diagnostics) return;
    const char *message = JS_ToCString(ctx, value);
    fprintf(stderr, "QuickJS: %s\n", message ? message : "exception conversion failed");
    JS_FreeCString(ctx, message);
}

static void report_exception(JSContext *ctx) {
    JSValue value = JS_GetException(ctx);
    report_value(ctx, value);
    JS_FreeValue(ctx, value);
}

static void rejection(JSContext *ctx, JSValueConst promise, JSValueConst reason,
                      JS_BOOL handled, void *opaque) {
    (void)promise;
    Host *host = opaque;
    host->unhandled_rejections += handled ? -1 : 1;
    if (!handled) report_value(ctx, reason);
}

static JSValue native_probe(JSContext *ctx, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self; (void)argc; (void)argv;
    return JS_NewInt32(ctx, quicktui_native_probe());
}

static JSValue print(JSContext *ctx, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self;
    for (int i = 0; i < argc; i++) {
        const char *value = JS_ToCString(ctx, argv[i]);
        if (!value) return JS_EXCEPTION;
        if (i) fputc(' ', stdout);
        fputs(value, stdout);
        JS_FreeCString(ctx, value);
    }
    fputc('\n', stdout);
    return JS_UNDEFINED;
}

int quicktui_eval(const char *source, size_t len, int diagnostics) {
    int result = 1;
    Host host = { .diagnostics = diagnostics };
    JSRuntime *runtime = JS_NewRuntime();
    if (!runtime) return result;
    JS_SetMemoryLimit(runtime, 64 * 1024 * 1024);
    JSContext *ctx = JS_NewContext(runtime);
    if (!ctx) { JS_FreeRuntime(runtime); return result; }
    JS_SetContextOpaque(ctx, &host);
    JS_SetHostPromiseRejectionTracker(runtime, rejection, &host);
    JSValue global = JS_GetGlobalObject(ctx);
    int registered = JS_SetPropertyStr(ctx, global, "nativeProbe",
        JS_NewCFunction(ctx, native_probe, "nativeProbe", 0));
    if (registered >= 0) registered = JS_SetPropertyStr(ctx, global, "print",
        JS_NewCFunction(ctx, print, "print", 1));
    JS_FreeValue(ctx, global);
    if (registered < 0) { report_exception(ctx); goto cleanup; }
    JSValue value = JS_Eval(ctx, source, len, "app.js", JS_EVAL_TYPE_GLOBAL);
    int failed = JS_IsException(value);
    JS_FreeValue(ctx, value);
    if (failed) { report_exception(ctx); goto cleanup; }
    for (unsigned jobs = 0; JS_IsJobPending(runtime); jobs++) {
        if (jobs == 10000) {
            if (diagnostics) fputs("QuickJS: pending-job limit exceeded\n", stderr);
            goto cleanup;
        }
        JSContext *job_ctx = NULL;
        if (JS_ExecutePendingJob(runtime, &job_ctx) < 0) {
            report_exception(job_ctx);
            goto cleanup;
        }
    }
    result = host.unhandled_rejections != 0;
cleanup:
    JS_FreeContext(ctx);
    JS_FreeRuntime(runtime);
    return result;
}
