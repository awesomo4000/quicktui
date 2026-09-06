#include "native_bridge.h"
#include <pthread.h>
#include <math.h>

// The application owns one runtime and one thread. The four callbacks are
// OpenTUI's global log, per-library event sink, Yoga measure, and Yoga dirtied.
static JSContext *callback_context;
static pthread_t owner;
static JSValue callbacks[4];
static JSValue callback_error;

int qt_pointer(JSContext *ctx, JSValueConst value, void **out) {
    if (JS_IsNull(value) || JS_IsUndefined(value)) { *out = NULL; return 0; }
    if (JS_IsNumber(value)) {
        double number;
        if (JS_ToFloat64(ctx,&number,value)<0) return -1;
        if (number==0) { *out=NULL; return 0; }
    }
    if (JS_IsBigInt(ctx, value)) {
        int64_t address;
        if (JS_ToBigInt64(ctx, &address, value) < 0) return -1;
        *out = (void *)(uintptr_t)address;
        return 0;
    }
    if (!JS_IsObject(value)) {
        JS_ThrowTypeError(ctx, "Native pointers must be BigInt or byte storage"); return -1;
    }
    JSValue backing = JS_GetPropertyStr(ctx, value, "buffer");
    if (JS_IsException(backing)) return -1;
    size_t size;
    if (JS_IsUndefined(backing)) {
        JS_FreeValue(ctx, backing);
        *out = JS_GetArrayBuffer(ctx, &size, value);
        return *out ? 0 : -1;
    }
    uint8_t *bytes = JS_GetArrayBuffer(ctx, &size, backing);
    JS_FreeValue(ctx, backing);
    if (!bytes) return -1;
    JSValue offset_value = JS_GetPropertyStr(ctx, value, "byteOffset");
    int64_t offset;
    int status = JS_ToInt64(ctx, &offset, offset_value);
    JS_FreeValue(ctx, offset_value);
    if (status < 0) return -1;
    if (offset < 0 || (uint64_t)offset > size) { JS_ThrowRangeError(ctx, "Byte view offset is out of range"); return -1; }
    *out = bytes + offset;
    return 0;
}

static void invoke(int kind, int count, JSValue *args) {
    JSContext *ctx = callback_context;
    if (!ctx) return;
    JSValue result = JS_Call(ctx, callbacks[kind], JS_UNDEFINED, count, args);
    for (int i=0; i<count; i++) JS_FreeValue(ctx,args[i]);
    if (JS_IsException(result)) {
        JSValue error=JS_GetException(ctx);
        if(JS_IsUndefined(callback_error)) callback_error=error;
        else JS_FreeValue(ctx,error);
    }
    JS_FreeValue(ctx,result);
}
static bool ready(int kind) {
    return callback_context && pthread_equal(owner,pthread_self()) && !JS_IsUndefined(callbacks[kind]);
}
static void log_callback(uint8_t level, void *message, uint32_t length) {
    if(!ready(0)) return;
    JSContext *ctx=callback_context;
    JSValue args[]={JS_NewUint32(ctx,level),JS_NewBigUint64(ctx,(uintptr_t)message),JS_NewUint32(ctx,length)};
    invoke(0,3,args);
}
static void event_callback(void *name,uint32_t name_len,void *data,uint32_t data_len) {
    if(!ready(1)) return;
    JSContext *ctx=callback_context;
    JSValue args[]={JS_NewBigUint64(ctx,(uintptr_t)name),JS_NewUint32(ctx,name_len),JS_NewBigUint64(ctx,(uintptr_t)data),JS_NewUint32(ctx,data_len)};
    invoke(1,4,args);
}
static void measure_callback(void *node,float width,uint32_t width_mode,float height,uint32_t height_mode) {
    if(!ready(2)) return;
    JSContext *ctx=callback_context;
    JSValue args[]={JS_NewBigUint64(ctx,(uintptr_t)node),JS_NewFloat64(ctx,width),JS_NewUint32(ctx,width_mode),JS_NewFloat64(ctx,height),JS_NewUint32(ctx,height_mode)};
    invoke(2,5,args);
}
static void dirtied_callback(void *node) {
    if(!ready(3)) return;
    JSContext *ctx=callback_context;
    JSValue args[]={JS_NewBigUint64(ctx,(uintptr_t)node)};
    invoke(3,1,args);
}
int qt_callback_failed(JSContext *ctx) {
    if(JS_IsUndefined(callback_error)) return 0;
    JSValue error=callback_error; callback_error=JS_UNDEFINED;
    JS_Throw(ctx,error);
    return 1;
}
static JSValue pointer(JSContext *ctx,JSValueConst self,int argc,JSValueConst *argv) {
    (void)self;
    void *address;
    if(argc!=1) return JS_ThrowTypeError(ctx,"pointer expects one argument");
    if(qt_pointer(ctx,argv[0],&address)<0) return JS_EXCEPTION;
    return JS_NewBigUint64(ctx,(uintptr_t)address);
}
static JSValue read_memory(JSContext *ctx,JSValueConst self,int argc,JSValueConst *argv) {
    (void)self;
    void *address; uint32_t length;
    if(argc!=2) return JS_ThrowTypeError(ctx,"readMemory expects two arguments");
    if(qt_pointer(ctx,argv[0],&address)<0 || JS_ToUint32(ctx,&length,argv[1])<0) return JS_EXCEPTION;
    if(length>16*1024*1024 || (!address && length)) return JS_ThrowRangeError(ctx,"Invalid native read length");
    return JS_NewArrayBufferCopy(ctx,address,length);
}
static JSValue callback(JSContext *ctx,JSValueConst self,int argc,JSValueConst *argv) {
    (void)self; uint32_t kind;
    if(argc!=2) return JS_ThrowTypeError(ctx,"callback expects two arguments");
    if(JS_ToUint32(ctx,&kind,argv[0])<0) return JS_EXCEPTION;
    if(kind>=4) return JS_ThrowRangeError(ctx,"Unknown callback kind");
    if(JS_IsNull(argv[1])) {JS_FreeValue(ctx,callbacks[kind]);callbacks[kind]=JS_UNDEFINED;return JS_UNDEFINED;}
    if(!JS_IsFunction(ctx,argv[1]) || !JS_IsUndefined(callbacks[kind])) return JS_ThrowTypeError(ctx,"Callback must be a function and its slot must be free");
    callbacks[kind]=JS_DupValue(ctx,argv[1]);
    uintptr_t addresses[]={(uintptr_t)log_callback,(uintptr_t)event_callback,(uintptr_t)measure_callback,(uintptr_t)dirtied_callback};
    return JS_NewBigUint64(ctx,addresses[kind]);
}
extern uint64_t qt_view_create(uint32_t buffer, const unsigned char *bytes, size_t length);
extern const unsigned char *qt_view_resolve(uint64_t token, size_t offset, size_t length);
extern void qt_view_release(uint64_t token);
extern uint32_t getBufferWidth(uint32_t), getBufferHeight(uint32_t);
extern void *bufferGetCharPtr(uint32_t), *bufferGetFgPtr(uint32_t), *bufferGetBgPtr(uint32_t), *bufferGetAttributesPtr(uint32_t);
static JSClassID buffer_view_class;
typedef struct { uint64_t token; } BufferView;
static void buffer_view_finalize(JSRuntime *runtime, JSValue value) {
    BufferView *view=JS_GetOpaque(value,buffer_view_class);
    if(view){qt_view_release(view->token);js_free_rt(runtime,view);}
}
JSValue qt_buffer_view(JSContext *ctx, uint32_t buffer, unsigned kind) {
    void *bytes=NULL;
    switch(kind){case 0:bytes=bufferGetCharPtr(buffer);break;case 1:bytes=bufferGetFgPtr(buffer);break;
        case 2:bytes=bufferGetBgPtr(buffer);break;case 3:bytes=bufferGetAttributesPtr(buffer);break;}
    if(!bytes)return JS_NULL;
    size_t cells=(size_t)getBufferWidth(buffer)*getBufferHeight(buffer);
    size_t unit=(kind==1||kind==2)?8:4;
    if(cells>SIZE_MAX/unit)return JS_ThrowRangeError(ctx,"Buffer view size overflow");
    JSValue result=JS_NewObjectClass(ctx,buffer_view_class);
    if(JS_IsException(result))return result;
    BufferView *view=js_malloc(ctx,sizeof(*view));
    if(!view){JS_FreeValue(ctx,result);return JS_EXCEPTION;}
    view->token=qt_view_create(buffer,bytes,cells*unit);
    if(!view->token){js_free(ctx,view);JS_FreeValue(ctx,result);return JS_ThrowOutOfMemory(ctx);}
    JS_SetOpaque(result,view);
    return result;
}
static JSValue read_buffer_view(JSContext *ctx, JSValueConst self, int argc, JSValueConst *argv) {
    (void)self;
    if(argc!=3)return JS_ThrowTypeError(ctx,"readBufferView expects a view, offset, and length");
    BufferView *view=JS_GetOpaque2(ctx,argv[0],buffer_view_class);
    if(!view)return JS_EXCEPTION;
    double offset,length;
    if(!JS_IsNumber(argv[1])||!JS_IsNumber(argv[2]))return JS_ThrowTypeError(ctx,"View bounds must be numbers");
    if(JS_ToFloat64(ctx,&offset,argv[1])<0||JS_ToFloat64(ctx,&length,argv[2])<0)return JS_EXCEPTION;
    if(!isfinite(offset)||!isfinite(length)||offset<0||length<0||floor(offset)!=offset||floor(length)!=length||
       offset>9007199254740991.0||length>16*1024*1024)return JS_ThrowRangeError(ctx,"Invalid view bounds");
    const unsigned char *bytes=qt_view_resolve(view->token,(size_t)offset,(size_t)length);
    if(!bytes)return JS_ThrowRangeError(ctx,"Stale buffer view or out-of-bounds read");
    return JS_NewArrayBufferCopy(ctx,bytes,(size_t)length);
}
int qt_register_ffi(JSContext *ctx,JSValue global) {
    callback_context=ctx;owner=pthread_self();callback_error=JS_UNDEFINED;
    for(int i=0;i<4;i++) callbacks[i]=JS_UNDEFINED;
    if(!buffer_view_class)JS_NewClassID(&buffer_view_class);
    const JSClassDef view_class={.class_name="TerminalBufferView",.finalizer=buffer_view_finalize};
    if(JS_NewClass(JS_GetRuntime(ctx),buffer_view_class,&view_class)<0)return -1;
    if(JS_SetPropertyStr(ctx,global,"__readBufferView",JS_NewCFunction(ctx,read_buffer_view,"__readBufferView",3))<0)return -1;
    if(JS_SetPropertyStr(ctx,global,"__pointer",JS_NewCFunction(ctx,pointer,"__pointer",1))<0) return -1;
    if(JS_SetPropertyStr(ctx,global,"__readMemory",JS_NewCFunction(ctx,read_memory,"__readMemory",2))<0) return -1;
    if(JS_SetPropertyStr(ctx,global,"__callback",JS_NewCFunction(ctx,callback,"__callback",2))<0) return -1;
    return qt_register_symbols(ctx,global);
}
void qt_close_ffi(JSContext *ctx) {
    // JS teardown unregisters native producers before this final root release.
    callback_context=NULL;
    for(int i=0;i<4;i++) JS_FreeValue(ctx,callbacks[i]);
    JS_FreeValue(ctx,callback_error);
    callback_error=JS_UNDEFINED;
}
