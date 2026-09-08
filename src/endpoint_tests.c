#define _POSIX_C_SOURCE 200809L
#include <unistd.h>
#include <poll.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>

#include "message_endpoint.h"
typedef MessageEndpoint Endpoint;
extern int quicktui_app_messages(const char*,size_t,int,const char*,const Endpoint*);
typedef struct {int mode,count,disconnected,sends,calls,late;} Fixture;
static int send_test(void *ctx,const unsigned char *p,size_t n){
 Fixture *f=ctx;f->sends++;
 if(n==5&&!memcmp(p,"close",5)){f->disconnected=1;return -1;}
 return n==4&&!memcmp(p,"full",4)?0:1;
}
static ptrdiff_t receive_test(void *ctx,unsigned char *p,size_t n){
 Fixture *f=ctx;f->calls++;
 if(f->disconnected){f->late++;return -3;}
 if(f->mode==0){f->disconnected=1;return -2;}
 if(f->mode==5){f->disconnected=1;return -3;}
 if(f->mode==1&&f->count==100)return -1;
 if(f->mode==2||f->mode==3)return -1;
 return snprintf((char*)p,n,"%d",f->count++);
}
extern int quicktui_endpoint_poll_tests(void);
// Stop at each callback boundary, including the remainder of a promise-job turn.
static int lifecycle_tests(void){
 const char *script=
 "let messages=0,ticks=0,jobs=0,frames=0,done;"
 "const check=v=>{if(!v)throw Error('lifecycle barrier regression')};"
 "const stop=()=>{done();__host.quit();check(__host.tryPostMessage('late')==='closed');check(!__host.postMessage('late'));};"
 "globalThis.__message=()=>{messages++;if(__host.example==='message')stop();};"
 "globalThis.__tick=()=>{ticks++;if(__host.example==='tick')stop();else if(__host.example==='job'){Promise.resolve().then(()=>{jobs++;stop()});Promise.resolve().then(()=>{jobs++});}};"
 "globalThis.__frame=()=>{frames++;if(__host.example==='frame')stop();};"
 "globalThis.__selfTest=()=>new Promise(resolve=>{done=resolve});"
 "globalThis.__shutdown=()=>{check(frames===(__host.example==='frame'?1:0));check(ticks===(__host.example==='message'?0:1));check(jobs===(__host.example==='job'?1:0));check(messages===(__host.example==='message'?1:32));};"
 "globalThis.__inspect=()=>'{\"effectMounted\":false,\"keys\":0}';";
 const char *stages[]={"message","tick","job","frame"};
 for(int repeat=0;repeat<8;repeat++)for(int i=0;i<4;i++){
  Fixture f={.mode=4};Endpoint e={.context=&f,.wake_fd=-1,.send=send_test,.receive=receive_test};
  if(quicktui_app_messages(script,strlen(script),1,stages[i],&e)||f.sends)return 50+i;
 }
 return 0;
}
int quicktui_endpoint_tests(void){
 if(quicktui_endpoint_poll_tests())return 40;
 int lifecycle=lifecycle_tests();if(lifecycle)return lifecycle;
 const char *script=
 "let count=0,ticks=0,frames=0,closed=0,done;"
 "const check=(v)=>{if(!v)throw Error('endpoint regression')};"
 "globalThis.__message=s=>{check(+s===count++);if(__host.example==='hup'&&count===33)check(__host.tryPostMessage('x')==='closed');};"
 "globalThis.__endpointClosed=r=>{check(++closed===1);check(__host.tryPostMessage('x')==='closed');check(!__host.postMessage('x'));};"
 "globalThis.__tick=()=>{ticks++;if(__host.example==='flood'&&ticks===12){check(count===384);check(frames===11);check(__host.tryPostMessage('close')==='closed');}"
 "if(closed&&ticks>=24){check(closed===1);if(__host.example==='hup')check(count===100);done();}};"
 "globalThis.__frame=()=>{frames++};"
 "globalThis.__shutdown=()=>{};globalThis.__inspect=()=>'{\"effectMounted\":false,\"keys\":0}';"
 "globalThis.__selfTest=()=>new Promise(resolve=>{done=resolve;check(__host.tryPostMessage('full')==='rejected');check(__host.tryPostMessage('ok')==='accepted');"
 "let threw=false;try{__host.tryPostMessage('x'.repeat(4097))}catch(e){threw=true}check(threw);});";
 for(int repeat=0;repeat<8;repeat++)for(int mode=0;mode<6;mode++){
  int fd[2];if(pipe(fd))return 1;
  Fixture f={.mode=mode};Endpoint e={.context=&f,.wake_fd=fd[0],.send=send_test,.receive=receive_test};
  if(mode==1){close(fd[1]);fd[1]=-1;}
  // Use a closed descriptor beyond the live fixture descriptors, never a system file.
  if(mode==2){int bad=fcntl(fd[0],F_DUPFD,1000);if(bad<0)return 2;close(bad);e.wake_fd=bad;}
  if(mode==3){close(fd[0]);fd[0]=-1;e.wake_fd=fd[1];}
  const char *name=mode==1?"hup":mode==4?"flood":"closed";
  int result=quicktui_app_messages(script,strlen(script),1,name,&e);
  for(int i=0;i<2;i++)if(fd[i]>=0)close(fd[i]);
  if(result)return 10+mode;
  if(f.sends!=(mode==4?3:2)||f.late)return 20+mode;
  if((mode==0||mode==2||mode==5)&&f.calls!=1)return 30+mode;
  // Darwin reports HUP on this broken pipe; Linux reports ERR. HUP has one drain attempt.
  if(mode==3&&(f.calls<1||f.calls>2))return 33;
 }
 return 0;
}

int quicktui_endpoint_terminal_test(void){
 int fd[2];if(pipe(fd))return 1;
 unsigned char wake=1;if(write(fd[1],&wake,1)!=1)return 2;
 Fixture f={.mode=4};Endpoint e={.context=&f,.wake_fd=fd[0],.send=send_test,.receive=receive_test};
 const char *script=
 "let count=0,ticks=0,frames=0,inputs=0,resizes=0,closed=0;"
 "globalThis.__message=s=>{if(+s!==count++)throw Error('FIFO');};"
 "globalThis.__tick=()=>{ticks++};globalThis.__frame=()=>{frames++};globalThis.__delay=()=>10;"
 "globalThis.__resize=()=>{resizes++};"
 "globalThis.__endpointClosed=()=>{if(++closed!==1)throw Error('repeated disconnect');};"
 "globalThis.__input=b=>{for(const ch of new Uint8Array(b)){"
 "if(ch===120){inputs++;__host.tryPostMessage('close');}"
 "if(ch===113){if(!count||!ticks||!frames||!inputs||!resizes||closed!==1)throw Error('event starvation');__host.quit();}}};"
 "globalThis.__shutdown=()=>{};";
 int result=quicktui_app_messages(script,strlen(script),0,"stress",&e);
 close(fd[0]);close(fd[1]);return result;
}
