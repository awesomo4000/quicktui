#ifndef QUICKTUI_MODULE_LOADER_H
#define QUICKTUI_MODULE_LOADER_H
#include "quickjs.h"
/* Source-module mode (see src/module_loader.c and src/modules.zig). */
int qt_modules_enabled(void);
/* Called with begin=1/0 around each module compile, so the host can pause
   execution deadlines. May be NULL. */
typedef void QtCompileHook(JSContext *ctx, int begin);
/* Install the loader realm, module hooks, and CommonJS runtime into ctx. */
int qt_modules_install(JSContext *ctx, QtCompileHook *hook);
/* Evaluate the entry graph; returns -1 with an exception pending in ctx. */
int qt_modules_run_entry(JSContext *ctx);
/* Record the graph of the configured entry and write a module pack.
   Returns 0 on success. Called by src/modules.zig buildPack. */
int quicktui_build_pack(const char *out_path);
/* Free the loader realm. Call after freeing the app context, before JS_FreeRuntime. */
void qt_modules_release(JSRuntime *rt);
#endif
