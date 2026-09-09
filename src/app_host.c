#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#include "native_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <poll.h>
#include <signal.h>
#include <errno.h>
#include <termios.h>
#include <sys/ioctl.h>
#include <fcntl.h>

#include "message_endpoint.h"
extern uint32_t createRenderer(uint32_t,uint32_t,uint8_t,uint8_t,void *);
extern void destroyRenderer(uint32_t,bool);
extern void setUseThread(uint32_t,bool);
extern void setKittyKeyboardFlags(uint32_t,uint8_t);
extern bool setTerminalEnvVar(uint32_t,const void *,uint32_t,const void *,uint32_t);
extern void setupTerminal(uint32_t,bool);
extern void enableMouse(uint32_t,bool);
extern uint32_t getCurrentBuffer(uint32_t);
extern uint8_t render(uint32_t,bool);
extern uint32_t bufferGetRealCharSize(uint32_t);
extern uint32_t bufferWriteResolvedChars(uint32_t,void *,uint32_t,bool);

typedef struct {
    uint32_t renderer;
    int renderer_borrowed;
    int keyboard_configured;uint8_t keyboard_flags;
    int width,height,headless;
    const MessageEndpoint *endpoint;
    int endpoint_closed;
    int endpoint_closing;
    int endpoint_notified;
    const char *endpoint_reason;
    int reloadable,reload_requested,reload_pending,preparing,frame_ready,generation;
    double deadline;
    char *next_source;size_t next_length;
    const char *snapshot;
    char notice[1024];
    int quit;
    int failed;
    char diagnostics[16384];
    size_t used;
} AppHost;
static volatile sig_atomic_t interrupted;
static volatile sig_atomic_t resized;
static volatile sig_atomic_t continued;
static volatile sig_atomic_t wake_write=-1;
static void signal_handler(int signal) {
    int saved_errno=errno;
    if(signal==SIGWINCH)resized=1;else if(signal==SIGCONT)continued=1;else interrupted=signal;
    // A self-pipe avoids losing a signal between the flag check and poll().
    if(wake_write>=0){unsigned char byte=1;(void)write(wake_write,&byte,1);}
    errno=saved_errno;
}
// Terminal resources belong to the host, independently of a UI runtime.
typedef struct {
    struct termios saved;
    int raw, signals;
    int wake[2];
    struct sigaction previous[5];
} TerminalSession;
static const int signal_numbers[]={SIGINT,SIGTERM,SIGHUP,SIGWINCH,SIGCONT};
static int terminal_open(TerminalSession *terminal,int headless) {
    struct sigaction action={0};
    if(pipe(terminal->wake)<0)return -1;
    for(int i=0;i<2;i++){
        if(fcntl(terminal->wake[i],F_SETFL,O_NONBLOCK)<0||
           fcntl(terminal->wake[i],F_SETFD,FD_CLOEXEC)<0)return -1;
    }
    wake_write=terminal->wake[1];
    action.sa_handler=signal_handler;sigemptyset(&action.sa_mask);
    for(int i=0;i<5;i++){
        if(sigaction(signal_numbers[i],&action,&terminal->previous[i])<0)return -1;
        terminal->signals++;
    }
    if(!headless){
        if(tcgetattr(STDIN_FILENO,&terminal->saved)<0)return -1;
        struct termios mode=terminal->saved;
        mode.c_lflag &= ~(ECHO|ICANON|IEXTEN|ISIG);
        mode.c_iflag &= ~(BRKINT|ICRNL|INPCK|ISTRIP|IXON);
        mode.c_cflag |= CS8;
        mode.c_cc[VMIN]=1;mode.c_cc[VTIME]=0;
        if(tcsetattr(STDIN_FILENO,TCSANOW,&mode)<0)return -1;
        terminal->raw=1;
    }
    return 0;
}
static void terminal_close(TerminalSession *terminal) {
    if(terminal->raw){
        // Fallback restoration also covers exceptions partway through setup.
        fputs("\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1006l\x1b[0m\x1b[?25h\x1b[?1049l",stdout);fflush(stdout);
        tcsetattr(STDIN_FILENO,TCSANOW,&terminal->saved);
        terminal->raw=0;
    }
    wake_write=-1;
    for(int i=0;i<terminal->signals;i++)sigaction(signal_numbers[i],&terminal->previous[i],NULL);
    terminal->signals=0;
    for(int i=0;i<2;i++)if(terminal->wake[i]>=0){close(terminal->wake[i]);terminal->wake[i]=-1;}
}
static int dispatch_allowed(const AppHost *host) {
    return !host->quit&&!host->failed&&!interrupted&&!host->reload_requested;
}
static void diagnostic(JSContext *ctx, const char *text) {
    AppHost *host=JS_GetContextOpaque(ctx);
    size_t available=sizeof(host->diagnostics)-host->used-1;
    size_t length=strlen(text);if(length>available)length=available;
    memcpy(host->diagnostics+host->used,text,length);host->used+=length;
    host->diagnostics[host->used]=0;
}
static void exception(JSContext *ctx) {
    AppHost *host=JS_GetContextOpaque(ctx);
    JSValue error=JS_GetException(ctx);
    const char *message=JS_ToCString(ctx,error);
    if(interrupted&&message&&!strcmp(message,"InternalError: interrupted")){
        host->quit=1;JS_FreeCString(ctx,message);JS_FreeValue(ctx,error);return;
    }
    host->failed=1;
    if(message){diagnostic(ctx,message);diagnostic(ctx,"\n");JS_FreeCString(ctx,message);}
    JSValue stack=JS_GetPropertyStr(ctx,error,"stack");
    if(JS_IsString(stack)){const char *text=JS_ToCString(ctx,stack);if(text){diagnostic(ctx,text);JS_FreeCString(ctx,text);}}
    JS_FreeValue(ctx,stack);JS_FreeValue(ctx,error);
}
static JSValue call(JSContext *ctx,const char *name,int argc,JSValue *argv) {
    JSValue global=JS_GetGlobalObject(ctx), fn=JS_GetPropertyStr(ctx,global,name);
    JSValue value=JS_IsFunction(ctx,fn)?JS_Call(ctx,fn,global,argc,argv):JS_UNDEFINED;
    JS_FreeValue(ctx,fn);JS_FreeValue(ctx,global);
    if(JS_IsException(value))exception(ctx);
    return value;
}
static void call_void(JSContext *ctx,const char *name) {JS_FreeValue(ctx,call(ctx,name,0,NULL));}
// The renderer is host-owned. JS owns only its widget tree and buffer wrappers.
static JSValue configure_keyboard(JSContext *ctx,JSValueConst self,int argc,JSValueConst *argv) {
    (void)self;uint32_t flags;AppHost *host=JS_GetContextOpaque(ctx);
    if(argc!=1)return JS_ThrowTypeError(ctx,"configureKeyboard expects flags");
    if(JS_ToUint32(ctx,&flags,argv[0])<0)return JS_EXCEPTION;
    if(flags>31)return JS_ThrowRangeError(ctx,"Invalid keyboard flags");
    if(host->keyboard_configured&&host->keyboard_flags!=flags)return JS_ThrowTypeError(ctx,"Keyboard options are fixed for the host lifetime");
    host->keyboard_configured=1;host->keyboard_flags=flags;return JS_UNDEFINED;
}
static JSValue borrow_renderer(JSContext *ctx,JSValueConst self,int argc,JSValueConst *argv) {
    (void)self;(void)argc;(void)argv;
    AppHost *host=JS_GetContextOpaque(ctx);
    if(host->renderer_borrowed)return JS_ThrowTypeError(ctx,"UI already borrowed the host renderer");
    if(!host->renderer){
        host->renderer=createRenderer(host->width,host->height,host->headless?1:0,1,NULL);
        if(!host->renderer)return JS_ThrowInternalError(ctx,"Cannot create host renderer");
        setUseThread(host->renderer,false);
        if(host->keyboard_configured)setKittyKeyboardFlags(host->renderer,host->keyboard_flags);
        const char *names[]={"TERM","COLORTERM","LANG","TMUX","STY","TERM_PROGRAM","TERM_PROGRAM_VERSION","ZELLIJ","ZELLIJ_SESSION_NAME","ZELLIJ_PANE_ID"};
        for(size_t i=0;i<sizeof(names)/sizeof(names[0]);i++){
            const char *value=getenv(names[i]);
            if(value&&!setTerminalEnvVar(host->renderer,names[i],strlen(names[i]),value,strlen(value)))
                return JS_ThrowInternalError(ctx,"Cannot configure host terminal");
        }
        if(!host->headless){setupTerminal(host->renderer,true);enableMouse(host->renderer,true);}
    }
    host->renderer_borrowed=1;
    return JS_NewUint32(ctx,host->renderer);
}
static void close_presenter(AppHost *host) {
    if(host->renderer){destroyRenderer(host->renderer,false);host->renderer=0;}
    host->renderer_borrowed=0;
}
// Headless tests verify the last complete text frame survives adapter and runtime teardown.
static unsigned char *presenter_text(AppHost *host,uint32_t *length) {
    uint32_t buffer=getCurrentBuffer(host->renderer);
    *length=bufferGetRealCharSize(buffer);
    unsigned char *bytes=malloc((size_t)*length+1);
    if(bytes)*length=bufferWriteResolvedChars(buffer,bytes,*length,false);
    return bytes;
}
static double monotonic_ms(void) {
    struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec*1000.0+t.tv_nsec/1e6;
}
static JSValue can_dispatch(JSContext *ctx,JSValueConst self,int argc,JSValueConst *argv) {
    (void)self;(void)argc;(void)argv;return JS_NewBool(ctx,dispatch_allowed(JS_GetContextOpaque(ctx)));
}
static JSValue request_reload(JSContext *ctx,JSValueConst self,int argc,JSValueConst *argv) {
    (void)self;AppHost *host=JS_GetContextOpaque(ctx);
    if(!host->reloadable||host->preparing||!dispatch_allowed(host))return JS_ThrowTypeError(ctx,"Reload is not available in this phase");
    if(host->reload_pending)return JS_UNDEFINED; // Coalesce while completing input.
    if(argc&& !JS_IsUndefined(argv[0])){
        if(!JS_IsString(argv[0]))return JS_ThrowTypeError(ctx,"Replacement bundle must be a string");
        size_t length;const char *text=JS_ToCStringLen(ctx,&length,argv[0]);if(!text)return JS_EXCEPTION;
        if(length>16*1024*1024){JS_FreeCString(ctx,text);return JS_ThrowRangeError(ctx,"Replacement bundle exceeds 16 MiB");}
        host->next_source=malloc(length+1);
        if(host->next_source){memcpy(host->next_source,text,length);host->next_source[length]=0;host->next_length=length;}
        JS_FreeCString(ctx,text);
        if(!host->next_source)return JS_ThrowOutOfMemory(ctx);
    }
    JSValue ready=call(ctx,"__inputReadyForReload",0,NULL);
    // Missing readiness hooks retain the original immediate behavior for custom hosts.
    int safe=JS_IsUndefined(ready)||JS_ToBool(ctx,ready)>0;JS_FreeValue(ctx,ready);
    if(safe)host->reload_requested=1;else host->reload_pending=1;
    return JS_UNDEFINED;
}
static JSValue present_frame(JSContext *ctx,JSValueConst self,int argc,JSValueConst *argv) {
    (void)self;(void)argc;(void)argv;AppHost *host=JS_GetContextOpaque(ctx);
    if(!dispatch_allowed(host)||!host->renderer)return JS_UNDEFINED;
    host->frame_ready=1;
    if(!host->preparing)render(host->renderer,false);
    return qt_callback_failed(ctx)?JS_EXCEPTION:JS_UNDEFINED;
}
static JSValue now(JSContext *ctx,JSValueConst self,int argc,JSValueConst *argv) {
    (void)self;(void)argc;(void)argv;
    struct timespec time;clock_gettime(CLOCK_MONOTONIC,&time);
    return JS_NewFloat64(ctx,time.tv_sec*1000.0+time.tv_nsec/1e6);
}
static JSValue write_log(JSContext *ctx,JSValueConst self,int argc,JSValueConst *argv) {
    (void)self;
    if(argc){const char *text=JS_ToCString(ctx,argv[0]);if(!text)return JS_EXCEPTION;diagnostic(ctx,text);JS_FreeCString(ctx,text);}
    return JS_UNDEFINED;
}
static JSValue quit(JSContext *ctx,JSValueConst self,int argc,JSValueConst *argv) {
    (void)self;(void)argc;(void)argv;((AppHost*)JS_GetContextOpaque(ctx))->quit=1;return JS_UNDEFINED;
}
static void disconnect_endpoint(AppHost *host,const char *reason) {
    if(host->endpoint_closed)return;
    host->endpoint_closed=1;host->endpoint_reason=reason;
}
static int endpoint_fd(AppHost *host) {
    return host->endpoint&&!host->endpoint_closed&&!host->endpoint_closing?host->endpoint->wake_fd:-1;
}
static void endpoint_poll(AppHost *host,short events) {
    if(events&POLLNVAL)disconnect_endpoint(host,"invalid-descriptor");
    else if(events&POLLERR)disconnect_endpoint(host,"descriptor-error");
    else if(events&POLLHUP)host->endpoint_closing=1;
}
// Deterministic flag cases supplement OS-specific disposable pipe fixtures.
int quicktui_endpoint_poll_tests(void) {
    AppHost error={0}, invalid={0}, hangup={0};
    endpoint_poll(&error,POLLERR|POLLIN);
    endpoint_poll(&invalid,POLLNVAL|POLLHUP);
    endpoint_poll(&hangup,POLLHUP|POLLIN);
    return !error.endpoint_closed||strcmp(error.endpoint_reason,"descriptor-error")||
        !invalid.endpoint_closed||strcmp(invalid.endpoint_reason,"invalid-descriptor")||
        hangup.endpoint_closed||!hangup.endpoint_closing;
}
static JSValue send_message(JSContext *ctx,int argc,JSValueConst *argv,int detailed) {
    AppHost *host=JS_GetContextOpaque(ctx);
    if(!host->endpoint)return JS_ThrowTypeError(ctx,"No native message endpoint");
    if(argc!=1||!JS_IsString(argv[0]))return JS_ThrowTypeError(ctx,"postMessage expects a string");
    size_t length;const char *bytes=JS_ToCStringLen(ctx,&length,argv[0]);
    if(!bytes)return JS_EXCEPTION;
    if(length>4096){JS_FreeCString(ctx,bytes);return JS_ThrowRangeError(ctx,"Message exceeds 4096 bytes");}
    int result=host->preparing||!dispatch_allowed(host)||host->endpoint_closed||host->endpoint_closing?-1:host->endpoint->send(host->endpoint->context,(const unsigned char *)bytes,length);
    JS_FreeCString(ctx,bytes);
    if(result<0&&!host->preparing&&dispatch_allowed(host)&&!host->endpoint_closing)disconnect_endpoint(host,result==-1?"closed":"send-error");
    return detailed?JS_NewString(ctx,result>0?"accepted":result==0?"rejected":"closed"):JS_NewBool(ctx,result>0);
}
static JSValue post_message(JSContext *ctx,JSValueConst self,int argc,JSValueConst *argv) {
    (void)self;return send_message(ctx,argc,argv,0);
}
static JSValue try_post_message(JSContext *ctx,JSValueConst self,int argc,JSValueConst *argv) {
    (void)self;return send_message(ctx,argc,argv,1);
}
static JSValue take_buffer(JSContext *ctx,JSValueConst self,int argc,JSValueConst *argv) {
    (void)self;
    AppHost *host=JS_GetContextOpaque(ctx);
    const MessageEndpoint *endpoint=host->endpoint;
    if(host->endpoint_closed||!endpoint||!endpoint->borrow_buffer||!endpoint->release_buffer)return JS_ThrowTypeError(ctx,"No binary endpoint");
    uint32_t id;
    if(argc!=1)return JS_ThrowTypeError(ctx,"takeBuffer expects a buffer ID");
    if(JS_ToUint32(ctx,&id,argv[0])<0)return JS_EXCEPTION;
    size_t length=0;
    const unsigned char *bytes=endpoint->borrow_buffer(endpoint->context,id,&length);
    if(!bytes)return JS_NULL;
    JSValue result=length<=4*1024*1024?JS_NewArrayBufferCopy(ctx,bytes,length):JS_ThrowRangeError(ctx,"Binary payload exceeds 4 MiB");
    endpoint->release_buffer(endpoint->context);
    return result;
}
static void messages(JSContext *ctx) {
    AppHost *host=JS_GetContextOpaque(ctx);
    if(!host->endpoint||host->endpoint_closed)return;
    // Bound work per turn so output floods cannot monopolize UI/input.
    for(int i=0;i<32&&dispatch_allowed(host)&&!host->endpoint_closed;i++){
        unsigned char bytes[4096];
        ptrdiff_t length=host->endpoint->receive(host->endpoint->context,bytes,sizeof(bytes));
        if(length<0){
            if(length<=-2||host->endpoint_closing)disconnect_endpoint(host,length==-3?"receive-error":"closed");
            break;
        }
        if((size_t)length>sizeof(bytes)){host->failed=1;diagnostic(ctx,"Invalid native message length\n");break;}
        JSValue message=JS_NewStringLen(ctx,(const char *)bytes,(size_t)length);
        JS_FreeValue(ctx,call(ctx,"__message",1,&message));JS_FreeValue(ctx,message);
    }
}
static void rejection(JSContext *ctx,JSValueConst promise,JSValueConst reason,JS_BOOL handled,void *opaque) {
    (void)promise;(void)opaque;
    if(!handled){JS_Throw(ctx,JS_DupValue(ctx,reason));exception(ctx);}
}
static int interrupt_js(JSRuntime *runtime,void *opaque) {
    (void)runtime;AppHost *host=opaque;return interrupted || (host&&host->deadline&&monotonic_ms()>host->deadline);
}
static void dimensions(int *width,int *height) {
    struct winsize size;
    *width=80;*height=24;
    if(ioctl(STDOUT_FILENO,TIOCGWINSZ,&size)==0){if(size.ws_col)*width=size.ws_col;if(size.ws_row)*height=size.ws_row;}
}
static void step(JSContext *ctx,JSRuntime *runtime) {
    AppHost *host=JS_GetContextOpaque(ctx);
    if(!dispatch_allowed(host))return;
    if(continued){
        continued=0;JSValue reason=JS_NewString(ctx,"resume");
        JS_FreeValue(ctx,call(ctx,"__inputReset",1,&reason));JS_FreeValue(ctx,reason);
    }
    if(!host->preparing)messages(ctx);
    if(!dispatch_allowed(host))return;
    if(!host->preparing&&host->endpoint_closed&&!host->endpoint_notified){
        host->endpoint_notified=1;
        JSValue reason=JS_NewString(ctx,host->endpoint_reason);
        JS_FreeValue(ctx,call(ctx,"__endpointClosed",1,&reason));JS_FreeValue(ctx,reason);
    }
    if(!dispatch_allowed(host))return;
    call_void(ctx,"__tick");
    for(int n=0;n<128&&dispatch_allowed(host)&&JS_IsJobPending(runtime);n++){
        JSContext *job_ctx=NULL;
        if(JS_ExecutePendingJob(runtime,&job_ctx)<0){exception(job_ctx);break;}
    }
    if(dispatch_allowed(host))call_void(ctx,"__frame");
}
static void input(JSContext *ctx,const void *bytes,size_t length) {
    JSValue values[]={JS_NewArrayBufferCopy(ctx,bytes,length),JS_NewFloat64(ctx,monotonic_ms())};
    JS_FreeValue(ctx,call(ctx,"__input",2,values));JS_FreeValue(ctx,values[0]);JS_FreeValue(ctx,values[1]);
}
static int expect_text(JSContext *ctx,const char *needle) {
    JSValue snapshot=call(ctx,"__snapshot",0,NULL);
    const char *text=JS_ToCString(ctx,snapshot);
    int ok=text&&strstr(text,needle);
    if(!ok){diagnostic(ctx,"Missing snapshot text: ");diagnostic(ctx,needle);diagnostic(ctx,"\n");if(text)diagnostic(ctx,text);}
    JS_FreeCString(ctx,text);JS_FreeValue(ctx,snapshot);
    return ok;
}
static void configure_ui(AppHost *host,JSContext *ctx,const char *source,size_t length,const char *example,int *ffi) {
    JSValue global=JS_GetGlobalObject(ctx), services=JS_NewObject(ctx), env=JS_NewObject(ctx);
    if(host->endpoint){JS_SetPropertyStr(ctx,services,"postMessage",JS_NewCFunction(ctx,post_message,"postMessage",1));JS_SetPropertyStr(ctx,services,"tryPostMessage",JS_NewCFunction(ctx,try_post_message,"tryPostMessage",1));}
    if(host->endpoint&&host->endpoint->borrow_buffer&&host->endpoint->release_buffer)JS_SetPropertyStr(ctx,services,"takeBuffer",JS_NewCFunction(ctx,take_buffer,"takeBuffer",1));
    if(host->reloadable){
        JS_SetPropertyStr(ctx,services,"requestReload",JS_NewCFunction(ctx,request_reload,"requestReload",1));
        JS_SetPropertyStr(ctx,services,"generation",JS_NewInt32(ctx,host->generation));
        JS_SetPropertyStr(ctx,services,"reloadState",JS_NewString(ctx,host->snapshot?host->snapshot:"null"));
        JS_SetPropertyStr(ctx,services,"reloadNotice",JS_NewString(ctx,host->notice));
    }
    JS_SetPropertyStr(ctx,services,"configureKeyboard",JS_NewCFunction(ctx,configure_keyboard,"configureKeyboard",1));
    JS_SetPropertyStr(ctx,services,"canDispatch",JS_NewCFunction(ctx,can_dispatch,"canDispatch",0));
    JS_SetPropertyStr(ctx,services,"presentFrame",JS_NewCFunction(ctx,present_frame,"presentFrame",0));
    JS_SetPropertyStr(ctx,services,"borrowRenderer",JS_NewCFunction(ctx,borrow_renderer,"borrowRenderer",0));
    JS_SetPropertyStr(ctx,services,"now",JS_NewCFunction(ctx,now,"now",0));
    JS_SetPropertyStr(ctx,services,"write",JS_NewCFunction(ctx,write_log,"write",1));
    JS_SetPropertyStr(ctx,services,"quit",JS_NewCFunction(ctx,quit,"quit",0));
    JS_SetPropertyStr(ctx,services,"width",JS_NewInt32(ctx,host->width));
    JS_SetPropertyStr(ctx,services,"height",JS_NewInt32(ctx,host->height));
    JS_SetPropertyStr(ctx,services,"headless",JS_NewBool(ctx,host->headless));
    JS_SetPropertyStr(ctx,services,"example",JS_NewString(ctx,example));
    #ifdef __APPLE__
    JS_SetPropertyStr(ctx,services,"platform",JS_NewString(ctx,"darwin"));
    #else
    JS_SetPropertyStr(ctx,services,"platform",JS_NewString(ctx,"linux"));
    #endif
    #ifdef __aarch64__
    JS_SetPropertyStr(ctx,services,"arch",JS_NewString(ctx,"arm64"));
    #else
    JS_SetPropertyStr(ctx,services,"arch",JS_NewString(ctx,"x64"));
    #endif
    const char *env_names[]={"TERM","COLORTERM","LANG","TMUX","STY","TERM_PROGRAM","TERM_PROGRAM_VERSION","ZELLIJ","ZELLIJ_SESSION_NAME","ZELLIJ_PANE_ID"};
    for(size_t i=0;i<sizeof(env_names)/sizeof(env_names[0]);i++){const char *value=getenv(env_names[i]);if(value)JS_SetPropertyStr(ctx,env,env_names[i],JS_NewString(ctx,value));}
    JS_SetPropertyStr(ctx,services,"env",env);
    JS_SetPropertyStr(ctx,global,"__host",services);
    *ffi=1;
    if(qt_register_ffi(ctx,global)<0){JS_FreeValue(ctx,global);exception(ctx);return;}
    JS_FreeValue(ctx,global);
    JSValue result=JS_Eval(ctx,source,length,"examples.js",JS_EVAL_TYPE_GLOBAL);
    if(JS_IsException(result))exception(ctx);
    JS_FreeValue(ctx,result);
}
int quicktui_app_messages(const char *source,size_t length,int headless,const char *example,const MessageEndpoint *endpoint) {
    AppHost host={.endpoint=endpoint,.headless=headless};
    unsigned char *retained_text=NULL;uint32_t retained_length=0;
    TerminalSession terminal={.wake={-1,-1}};
    int ffi=0;
    interrupted=0;resized=0;continued=0;
    if(!headless&&(!isatty(STDIN_FILENO)||!isatty(STDOUT_FILENO))){fputs("QuickTUI needs a terminal; use --self-test for headless checks.\n",stderr);return 1;}
    JSRuntime *runtime=JS_NewRuntime();if(!runtime)return 1;
    JS_SetMemoryLimit(runtime,128*1024*1024);
    JSContext *ctx=JS_NewContext(runtime);if(!ctx){JS_FreeRuntime(runtime);return 1;}
    JS_SetContextOpaque(ctx,&host);
    JS_SetHostPromiseRejectionTracker(runtime,rejection,&host);
    JS_SetInterruptHandler(runtime,interrupt_js,&host);
    if(terminal_open(&terminal,headless)<0){host.failed=1;goto cleanup;}
    int width,height;dimensions(&width,&height);if(headless){width=80;height=24;}
    host.width=width;host.height=height;
    configure_ui(&host,ctx,source,length,example,&ffi);
    if(host.failed)goto cleanup;
    if(headless){
        JSValue test_global=JS_GetGlobalObject(ctx);
        JSValue custom_test=JS_GetPropertyStr(ctx,test_global,"__selfTest");
        int has_custom_test=JS_IsFunction(ctx,custom_test);
        JS_FreeValue(ctx,custom_test);JS_FreeValue(ctx,test_global);
        if(has_custom_test){
            JSValue test_result=call(ctx,"__selfTest",0,NULL);
            for(int i=0;i<30000&&dispatch_allowed(&host)&&JS_PromiseState(ctx,test_result)==JS_PROMISE_PENDING;i++){step(ctx,runtime); {struct pollfd fd={.fd=endpoint_fd(&host),.events=POLLIN};poll(&fd,1,JS_IsJobPending(runtime)||(host.endpoint_closing&&!host.endpoint_closed)?0:1);endpoint_poll(&host,fd.revents);}}
            if(!host.failed&&JS_PromiseState(ctx,test_result)==JS_PROMISE_PENDING){diagnostic(ctx,"Example self-test did not settle\n");host.failed=1;}
            if(!host.failed&&JS_PromiseState(ctx,test_result)==JS_PROMISE_REJECTED){JS_Throw(ctx,JS_PromiseResult(ctx,test_result));exception(ctx);}
            JS_FreeValue(ctx,test_result);goto cleanup;
        }
        for(int i=0;i<4;i++)step(ctx,runtime);
        if(!expect_text(ctx,"Count: 0"))host.failed=1;
        if(!expect_text(ctx,"日本語")||!expect_text(ctx,"👩‍💻")||!expect_text(ctx,"é"))host.failed=1;
        input(ctx,"  ",2);
        for(int i=0;i<4;i++)step(ctx,runtime);
        if(!expect_text(ctx,"Count: 2"))host.failed=1;
        input(ctx,"\x1b[",2);input(ctx,"B",1);
        for(int i=0;i<4;i++)step(ctx,runtime);
        if(!expect_text(ctx,"Count: 1"))host.failed=1;
        input(ctx,"r",1);
        for(int i=0;i<4;i++)step(ctx,runtime);
        if(!expect_text(ctx,"Count: 0"))host.failed=1;
        JSValue size[]={JS_NewInt32(ctx,64),JS_NewInt32(ctx,20)};
        JS_FreeValue(ctx,call(ctx,"__resize",2,size));
        for(int i=0;i<4;i++)step(ctx,runtime);
        if(!expect_text(ctx,"Terminal 64 × 20"))host.failed=1;
        goto cleanup;
    }
    while(!host.quit&&!host.failed&&!interrupted){
        if(resized){resized=0;dimensions(&width,&height);JSValue size[]={JS_NewInt32(ctx,width),JS_NewInt32(ctx,height)};JS_FreeValue(ctx,call(ctx,"__resize",2,size));}
        step(ctx,runtime);
        if(host.quit||host.failed||interrupted)break;
        int timeout=-1;
        JSValue delay=call(ctx,"__delay",0,NULL);JS_ToInt32(ctx,&timeout,delay);JS_FreeValue(ctx,delay);
        if(!dispatch_allowed(&host))break;
        if(JS_IsJobPending(runtime)||(host.endpoint_closing&&!host.endpoint_closed))timeout=0;
        struct pollfd fds[]={{.fd=STDIN_FILENO,.events=POLLIN},{.fd=terminal.wake[0],.events=POLLIN},{.fd=endpoint_fd(&host),.events=POLLIN}};
        int ready=poll(fds,3,timeout);
        if(ready<0){if(errno==EINTR)continue;host.failed=1;break;}
        if(ready>0){
            endpoint_poll(&host,fds[2].revents);
            if(fds[1].revents&POLLIN){unsigned char bytes[64];while(read(terminal.wake[0],bytes,sizeof(bytes))>0){}}
            if(fds[0].revents&POLLIN){unsigned char bytes[4096];ssize_t count=read(STDIN_FILENO,bytes,sizeof(bytes));if(count<=0)break;input(ctx,bytes,(size_t)count);}
            if(fds[0].revents&(POLLHUP|POLLERR|POLLNVAL))break;
        }
    }
cleanup:
    if(headless&&host.renderer)retained_text=presenter_text(&host,&retained_length);
    // Stop interrupting JS so the UI adapter can unmount while native resources are live.
    JS_SetInterruptHandler(runtime,NULL,NULL);
    call_void(ctx,"__shutdown");
    if(headless&&!host.failed){
        JSValue state=call(ctx,"__inspect",0,NULL);const char *text=JS_ToCString(ctx,state);
        // Legacy standalone demos report effectMounted; the shared core reports applicationMounted.
        if(!text||(!strstr(text,"\"applicationMounted\":false")&&!strstr(text,"\"effectMounted\":false"))||!strstr(text,"\"keys\":0"))host.failed=1;
        if(text&&strstr(text,"\"applicationMounted\":true"))host.failed=1;
        if(text&&strstr(text,"\"effectMounted\":")&&!strstr(text,"\"effectMounted\":false"))host.failed=1;
        JS_FreeCString(ctx,text);JS_FreeValue(ctx,state);
    }
    if(ffi)qt_close_ffi(ctx);
    JS_FreeContext(ctx);JS_FreeRuntime(runtime);qt_views_deinit();
    host.renderer_borrowed=0;
    if(headless&&host.renderer){
        uint32_t after_length=0;unsigned char *after=presenter_text(&host,&after_length);
        if(!retained_text||!after||retained_length!=after_length||memcmp(retained_text,after,retained_length)){
            host.failed=1;fputs("Host renderer lost its frame during UI retirement\n",stderr);
        }
        free(after);
    }
    free(retained_text);
    close_presenter(&host);
    terminal_close(&terminal);
    if(host.used)fputs(host.diagnostics,stderr);
    if(headless&&!host.failed)puts("Example self-test passed: input, UI updates, native rendering, and lifecycle cleanup.");
    return host.failed?1:0;
}

int quicktui_app(const char *source,size_t length,int headless,const char *example) {
    return quicktui_app_messages(source,length,headless,example,NULL);
}

// Experimental sequential replacement host. Only one JS context owns callbacks
// at a time. The renderer and application endpoint outlive every generation.
typedef struct { JSRuntime *runtime;JSContext *ctx;int ffi; } UiRuntime;
static void retire_ui(AppHost *host,UiRuntime *ui) {
    if(ui->ctx){
        host->deadline=monotonic_ms()+500;
        call_void(ui->ctx,"__shutdown");
        if(ui->ffi)qt_close_ffi(ui->ctx);
        JS_FreeContext(ui->ctx);
    }
    if(ui->runtime)JS_FreeRuntime(ui->runtime);
    qt_views_deinit();memset(ui,0,sizeof(*ui));host->renderer_borrowed=0;host->deadline=0;
}
static int prepare_ui(AppHost *host,UiRuntime *ui,const char *source,size_t length,const char *example) {
    host->preparing=1;host->frame_ready=0;host->deadline=monotonic_ms()+2000;
    ui->runtime=JS_NewRuntime();if(!ui->runtime){host->failed=1;return 0;}
    JS_SetMemoryLimit(ui->runtime,128*1024*1024);
    ui->ctx=JS_NewContext(ui->runtime);if(!ui->ctx){host->failed=1;return 0;}
    JS_SetContextOpaque(ui->ctx,host);
    JS_SetInterruptHandler(ui->runtime,interrupt_js,host);
    JS_SetHostPromiseRejectionTracker(ui->runtime,rejection,host);
    configure_ui(host,ui->ctx,source,length,example,&ui->ffi);
    while(dispatch_allowed(host)&&!host->frame_ready&&monotonic_ms()<host->deadline){
        step(ui->ctx,ui->runtime);
        if(!host->frame_ready)poll(NULL,0,1);
    }
    if(!host->frame_ready&&!host->quit&&!interrupted)host->failed=1;
    host->deadline=0;
    return dispatch_allowed(host)&&host->frame_ready;
}
static void activate_ui(AppHost *host,UiRuntime *ui) {
    // Coalesce resizes received while compiling/mounting before presentation.
    if(resized&&!host->headless){
        resized=0;dimensions(&host->width,&host->height);
        JSValue size[]={JS_NewInt32(ui->ctx,host->width),JS_NewInt32(ui->ctx,host->height)};
        JS_FreeValue(ui->ctx,call(ui->ctx,"__resize",2,size));
        call_void(ui->ctx,"__frame");
    }
    if(!dispatch_allowed(host))return;
    // Input and endpoint replies were never drained during preparation.
    host->preparing=0;render(host->renderer,false);
    if(qt_callback_failed(ui->ctx))exception(ui->ctx);
}
int quicktui_reload_app(const char *source,size_t length,int headless,const char *example,const MessageEndpoint *endpoint) {
    AppHost host={.endpoint=endpoint,.headless=headless,.reloadable=1,.generation=1};
    UiRuntime ui={0};TerminalSession terminal={.wake={-1,-1}};
    char *good_source=NULL,*state=NULL;
    interrupted=0;resized=0;continued=0;
    if(!headless&&(!isatty(0)||!isatty(1)))return 1;
    if(terminal_open(&terminal,headless)<0){host.failed=1;goto done;}
    dimensions(&host.width,&host.height);if(headless){host.width=80;host.height=24;}
    if(!prepare_ui(&host,&ui,source,length,example))goto done;
    activate_ui(&host,&ui);
    const double test_deadline=monotonic_ms()+30000;
    while(!host.quit&&!host.failed&&!interrupted){
        if(headless&&monotonic_ms()>test_deadline){host.failed=1;break;}
        if(resized){
            resized=0;dimensions(&host.width,&host.height);
            JSValue size[]={JS_NewInt32(ui.ctx,host.width),JS_NewInt32(ui.ctx,host.height)};
            JS_FreeValue(ui.ctx,call(ui.ctx,"__resize",2,size));
        }
        if(host.reload_pending){
            JSValue ready=call(ui.ctx,"__inputReadyForReload",0,NULL);
            if(JS_ToBool(ui.ctx,ready)>0){host.reload_pending=0;host.reload_requested=1;}
            JS_FreeValue(ui.ctx,ready);
        }
        step(ui.ctx,ui.runtime);
        if(host.reload_requested&&!host.quit&&!host.failed&&!interrupted){
            // Snapshot only after all regular event dispatch has stopped.
            host.deadline=monotonic_ms()+500;
            JSValue snapshot=call(ui.ctx,"__exportState",0,NULL);
            size_t state_length=0;const char *bytes=JS_IsString(snapshot)?JS_ToCStringLen(ui.ctx,&state_length,snapshot):NULL;
            char *next_state=NULL;
            if(bytes&&state_length<=1024*1024&&!memchr(bytes,0,state_length)){
                next_state=malloc(state_length+1);
                if(next_state){memcpy(next_state,bytes,state_length);next_state[state_length]=0;}
            }
            JS_FreeCString(ui.ctx,bytes);JS_FreeValue(ui.ctx,snapshot);host.deadline=0;
            if(!next_state){
                host.failed=0;host.reload_requested=0;free(host.next_source);host.next_source=NULL;
                JSValue message=JS_NewString(ui.ctx,"Snapshot failed; current UI retained");
                JS_FreeValue(ui.ctx,call(ui.ctx,"__reloadNotice",1,&message));JS_FreeValue(ui.ctx,message);
                continue;
            }
            retire_ui(&host,&ui);
            if(host.failed||host.quit||interrupted){free(next_state);break;}
            free(state);state=next_state;host.snapshot=state;
            host.reload_requested=0;host.generation++;
            char *candidate=host.next_source;size_t candidate_length=host.next_length;
            host.next_source=NULL;
            const char *selected=candidate?candidate:(good_source?good_source:source);
            size_t selected_length=candidate?candidate_length:length;
            host.notice[0]=0;
            if(!prepare_ui(&host,&ui,selected,selected_length,example)){
                snprintf(host.notice,sizeof(host.notice),"Replacement failed; restored previous bundle: %.850s",host.diagnostics);
                retire_ui(&host,&ui);free(candidate);candidate=NULL;
                if(host.quit||interrupted)break;
                host.failed=0;host.used=0;host.diagnostics[0]=0;
                if(!prepare_ui(&host,&ui,good_source?good_source:source,length,example))break;
            }
            if(candidate){free(good_source);good_source=candidate;length=candidate_length;}
            activate_ui(&host,&ui);
            continue;
        }
        if(!dispatch_allowed(&host))break;
        int timeout=10;
        struct pollfd fds[]={{.fd=headless?-1:0,.events=POLLIN},{.fd=terminal.wake[0],.events=POLLIN},{.fd=endpoint_fd(&host),.events=POLLIN}};
        int ready=poll(fds,3,timeout);
        if(ready<0){if(errno==EINTR)continue;host.failed=1;break;}
        endpoint_poll(&host,fds[2].revents);
        if(fds[1].revents&POLLIN){unsigned char bytes[64];while(read(terminal.wake[0],bytes,sizeof(bytes))>0){}}
        if(fds[0].revents&POLLIN){unsigned char bytes[4096];ssize_t n=read(0,bytes,sizeof(bytes));if(n<=0)break;input(ui.ctx,bytes,n);}
        if(fds[0].revents&(POLLHUP|POLLERR|POLLNVAL))break;
    }
done:
    host.reload_requested=1;retire_ui(&host,&ui);
    close_presenter(&host);terminal_close(&terminal);
    free(good_source);free(state);free(host.next_source);
    if(host.used)fputs(host.diagnostics,stderr);
    return host.failed?1:0;
}
