declare const __host:{requestReload?(source?:string):void,reloadState?:string,generation?:number,reloadNotice?:string,quit():void,tryPostMessage?(message:string):"accepted"|"rejected"|"closed",takeBuffer?(id:number):ArrayBuffer|null};
export function quit(){__host.quit()}
export function sendMessage(message:string){
  if(!__host.tryPostMessage)throw new Error("No native message endpoint");
  return __host.tryPostMessage(message);
}
export function takeBuffer(id:number){
  if(!__host.takeBuffer)throw new Error("No binary endpoint");
  return __host.takeBuffer(id);
}

/** Available only when the native caller opts into reload. */
export function getReloadInfo(){
  return {enabled:typeof __host.requestReload==="function",generation:__host.generation??1,notice:__host.reloadNotice??""};
}
/** Read application-owned JSON. The application validates and versions its shape. */
export function getReloadState<T>(fallback:T):T {
  return __host.reloadState===undefined||__host.reloadState==="null"?fallback:JSON.parse(__host.reloadState);
}
/** Replace the runtime after this callback. Omit source to reuse the last good bundle. */
export function requestReload(source?:string){
  if(!__host.requestReload)throw new Error("Reload is disabled by the native host");
  __host.requestReload(source);
}

