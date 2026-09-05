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

typedef struct {
    int quit;
    int failed;
    char diagnostics[16384];
    size_t used;
} AppHost;
static volatile sig_atomic_t interrupted;
static volatile sig_atomic_t resized;
static volatile sig_atomic_t wake_write=-1;
static void signal_handler(int signal) {
    int saved_errno=errno;
    if(signal==SIGWINCH)resized=1;else interrupted=signal;
    // A self-pipe avoids losing a signal between the flag check and poll().
    if(wake_write>=0){unsigned char byte=1;(void)write(wake_write,&byte,1);}
    errno=saved_errno;
}
static void diagnostic(JSContext *ctx, const char *text) {
    AppHost *host=JS_GetContextOpaque(ctx);
    size_t available=sizeof(host->diagnostics)-host->used-1;
    size_t length=strlen(text);if(length>available)length=available;
    memcpy(host->diagnostics+host->used,text,length);host->used+=length;
    host->diagnostics[host->used]=0;
}
static void exception(JSContext *ctx) {
    AppHost *host=JS_GetContextOpaque(ctx);host->failed=1;
    JSValue error=JS_GetException(ctx);
    const char *message=JS_ToCString(ctx,error);
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
static void rejection(JSContext *ctx,JSValueConst promise,JSValueConst reason,JS_BOOL handled,void *opaque) {
    (void)promise;(void)opaque;
    if(!handled){JS_Throw(ctx,JS_DupValue(ctx,reason));exception(ctx);}
}
static int interrupt_js(JSRuntime *runtime,void *opaque) {
    (void)runtime;(void)opaque;return interrupted && interrupted!=SIGWINCH;
}
static void dimensions(int *width,int *height) {
    struct winsize size;
    *width=80;*height=24;
    if(ioctl(STDOUT_FILENO,TIOCGWINSZ,&size)==0){if(size.ws_col)*width=size.ws_col;if(size.ws_row)*height=size.ws_row;}
}
static void step(JSContext *ctx,JSRuntime *runtime) {
    call_void(ctx,"__tick");
    for(int n=0;n<128&&JS_IsJobPending(runtime);n++){
        JSContext *job_ctx=NULL;
        if(JS_ExecutePendingJob(runtime,&job_ctx)<0){exception(job_ctx);break;}
    }
    call_void(ctx,"__frame");
}
static void input(JSContext *ctx,const void *bytes,size_t length) {
    JSValue value=JS_NewArrayBufferCopy(ctx,bytes,length);
    JS_FreeValue(ctx,call(ctx,"__input",1,&value));JS_FreeValue(ctx,value);
}
static int expect_text(JSContext *ctx,const char *needle) {
    JSValue snapshot=call(ctx,"__snapshot",0,NULL);
    const char *text=JS_ToCString(ctx,snapshot);
    int ok=text&&strstr(text,needle);
    if(!ok){diagnostic(ctx,"Missing snapshot text: ");diagnostic(ctx,needle);diagnostic(ctx,"\n");if(text)diagnostic(ctx,text);}
    JS_FreeCString(ctx,text);JS_FreeValue(ctx,snapshot);
    return ok;
}
int quicktui_app(const char *source,size_t length,int headless) {
    AppHost host={0};
    struct termios saved;
    int raw=0, signals=0, ffi=0;
    int wake[2]={-1,-1};
    const int signal_numbers[]={SIGINT,SIGTERM,SIGHUP,SIGWINCH};
    struct sigaction previous[4], action={0};
    interrupted=0;resized=0;
    if(!headless&&(!isatty(STDIN_FILENO)||!isatty(STDOUT_FILENO))){fputs("QuickTUI needs a terminal; use --self-test for headless checks.\n",stderr);return 1;}
    JSRuntime *runtime=JS_NewRuntime();if(!runtime)return 1;
    JS_SetMemoryLimit(runtime,128*1024*1024);
    JSContext *ctx=JS_NewContext(runtime);if(!ctx){JS_FreeRuntime(runtime);return 1;}
    JS_SetContextOpaque(ctx,&host);
    JS_SetHostPromiseRejectionTracker(runtime,rejection,&host);
    JS_SetInterruptHandler(runtime,interrupt_js,NULL);
    if(pipe(wake)<0){host.failed=1;goto cleanup;}
    for(int i=0;i<2;i++){
        if(fcntl(wake[i],F_SETFL,O_NONBLOCK)<0||fcntl(wake[i],F_SETFD,FD_CLOEXEC)<0){host.failed=1;goto cleanup;}
    }
    wake_write=wake[1];
    action.sa_handler=signal_handler;sigemptyset(&action.sa_mask);
    for(int i=0;i<4;i++){if(sigaction(signal_numbers[i],&action,&previous[i])<0){host.failed=1;goto cleanup;}signals++;}
    if(!headless){
        if(tcgetattr(STDIN_FILENO,&saved)<0){host.failed=1;goto cleanup;}
        struct termios mode=saved;
        mode.c_lflag &= ~(ECHO|ICANON|IEXTEN|ISIG);
        mode.c_iflag &= ~(BRKINT|ICRNL|INPCK|ISTRIP|IXON);
        mode.c_cflag |= CS8;
        mode.c_cc[VMIN]=1;mode.c_cc[VTIME]=0;
        if(tcsetattr(STDIN_FILENO,TCSANOW,&mode)<0){host.failed=1;goto cleanup;}raw=1;
    }
    int width,height;dimensions(&width,&height);if(headless){width=80;height=24;}
    JSValue global=JS_GetGlobalObject(ctx), services=JS_NewObject(ctx), env=JS_NewObject(ctx);
    JS_SetPropertyStr(ctx,services,"now",JS_NewCFunction(ctx,now,"now",0));
    JS_SetPropertyStr(ctx,services,"write",JS_NewCFunction(ctx,write_log,"write",1));
    JS_SetPropertyStr(ctx,services,"quit",JS_NewCFunction(ctx,quit,"quit",0));
    JS_SetPropertyStr(ctx,services,"width",JS_NewInt32(ctx,width));
    JS_SetPropertyStr(ctx,services,"height",JS_NewInt32(ctx,height));
    JS_SetPropertyStr(ctx,services,"headless",JS_NewBool(ctx,headless));
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
    ffi=1;
    if(qt_register_ffi(ctx,global)<0){JS_FreeValue(ctx,global);exception(ctx);goto cleanup;}
    JS_FreeValue(ctx,global);
    JSValue result=JS_Eval(ctx,source,length,"counter.js",JS_EVAL_TYPE_GLOBAL);
    if(JS_IsException(result))exception(ctx);
    JS_FreeValue(ctx,result);
    if(host.failed)goto cleanup;
    if(headless){
        JSValue test_global=JS_GetGlobalObject(ctx);
        JSValue custom_test=JS_GetPropertyStr(ctx,test_global,"__selfTest");
        int has_custom_test=JS_IsFunction(ctx,custom_test);
        JS_FreeValue(ctx,custom_test);JS_FreeValue(ctx,test_global);
        if(has_custom_test){
            JSValue test_result=call(ctx,"__selfTest",0,NULL);
            for(int i=0;i<10000&&!host.failed&&JS_PromiseState(ctx,test_result)==JS_PROMISE_PENDING;i++)step(ctx,runtime);
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
        if(JS_IsJobPending(runtime))timeout=0;
        struct pollfd fds[]={{.fd=STDIN_FILENO,.events=POLLIN},{.fd=wake[0],.events=POLLIN}};
        int ready=poll(fds,2,timeout);
        if(ready<0){if(errno==EINTR)continue;host.failed=1;break;}
        if(ready>0){
            if(fds[1].revents&POLLIN){unsigned char bytes[64];while(read(wake[0],bytes,sizeof(bytes))>0){}}
            if(fds[0].revents&POLLIN){unsigned char bytes[4096];ssize_t count=read(STDIN_FILENO,bytes,sizeof(bytes));if(count<=0)break;input(ctx,bytes,(size_t)count);}
            if(fds[0].revents&(POLLHUP|POLLERR|POLLNVAL))break;
        }
    }
cleanup:
    // Stop interrupting JS so React can unmount while native resources are live.
    JS_SetInterruptHandler(runtime,NULL,NULL);
    call_void(ctx,"__shutdown");
    if(headless&&!host.failed){
        JSValue state=call(ctx,"__inspect",0,NULL);const char *text=JS_ToCString(ctx,state);
        if(!text||!strstr(text,"\"effectMounted\":false")||!strstr(text,"\"keys\":0"))host.failed=1;
        JS_FreeCString(ctx,text);JS_FreeValue(ctx,state);
    }
    if(ffi)qt_close_ffi(ctx);
    if(raw){
        // Fallback restoration also covers exceptions partway through setup.
        fputs("\x1b[?1000l\x1b[?1002l\x1b[?1003l\x1b[?1006l\x1b[0m\x1b[?25h\x1b[?1049l",stdout);fflush(stdout);
        tcsetattr(STDIN_FILENO,TCSANOW,&saved);
    }
    for(int i=0;i<signals;i++)sigaction(signal_numbers[i],&previous[i],NULL);
    wake_write=-1;
    for(int i=0;i<2;i++)if(wake[i]>=0)close(wake[i]);
    JS_FreeContext(ctx);JS_FreeRuntime(runtime);
    if(host.used)fputs(host.diagnostics,stderr);
    if(headless&&!host.failed)puts("Example self-test passed: input, React updates, native rendering, and effect cleanup.");
    return host.failed?1:0;
}
