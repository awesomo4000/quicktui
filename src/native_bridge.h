#ifndef QUICKTUI_NATIVE_BRIDGE_H
#define QUICKTUI_NATIVE_BRIDGE_H
#include "quickjs.h"
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
int qt_pointer(JSContext *ctx, JSValueConst value, void **out);
int qt_callback_failed(JSContext *ctx);
int qt_register_symbols(JSContext *ctx, JSValue global);
int qt_register_ffi(JSContext *ctx, JSValue global);
void qt_close_ffi(JSContext *ctx);
#endif
