import React, { useEffect } from "../../vendor/js/node_modules/react";
import ReactReconciler from "../../vendor/js/node_modules/react-reconciler";
import { hostConfig } from "../../vendor/opentui/packages/react/src/reconciler/host-config";
import { Renderable, RootRenderable } from "../../vendor/opentui/packages/core/src/Renderable";
import { resolveRenderLib } from "../../vendor/opentui/packages/core/src/zig";
import { RGBA } from "../../vendor/opentui/packages/core/src/lib/RGBA";
import { EventEmitter } from "../../vendor/js/node_modules/events";
import { StdinParser } from "../../vendor/opentui/packages/core/src/lib/stdin-parser";
import { MouseRouter } from "./mouse";

declare const __host: {width:number,height:number,headless:boolean,env:Record<string,string>,quit():void};
declare const __timers: {tick():void,delay():number,clear():void};
let dirty=true;
let stopped=false;
let liveCount=0;
let liveTimer:ReturnType<typeof setTimeout>|undefined;
let container:any;
let native:any;
let root:RootRenderable;
let lib:ReturnType<typeof resolveRenderLib>;
export const keys=new EventEmitter();
let keyInterceptor:((key:any)=>boolean)|null=null;
export function interceptKeys(handler:((key:any)=>boolean)|null){keyInterceptor=handler}
export const graphicsState={confirmed:false};
const parser=new StdinParser({onTimeoutFlush:()=>drainInput()});
function drainInput(){parser.drain(event=>{
  if(event.type==="key"){
    if(keyInterceptor?.(event.key))return;
    if((event.key.ctrl&&event.key.name==="c")||event.key.name.toLowerCase()==="q"){__host.quit();return}
    keys.emit("key",event.key.name.toLowerCase());
  } else if(event.type==="mouse"){
    mouse.dispatch(event.event);
  } else if(event.type==="response"&&native){
    lib.processCapabilityResponse(native,event.sequence);
    context.capabilities=lib.getTerminalCapabilities(native) as any;
    const reply=event.sequence.match(/^\x1b_G([^;]*);([\s\S]*?)\x1b\\$/);
    if(reply&&reply[1].split(",").includes("i=31337")&&reply[2]==="OK"){
      graphicsState.confirmed=true;keys.emit("graphics",true);dirty=true;
    }
  }
})}
const lifecycle=new Set<any>();
const context=Object.assign(new EventEmitter(),{
  width:__host.width,height:__host.height,frameId:0,widthMethod:"unicode",capabilities:null,
  requestRender(){dirty=true},getLifecyclePasses:()=>lifecycle,
  registerLifecyclePass:(node:any)=>lifecycle.add(node),unregisterLifecyclePass:(node:any)=>lifecycle.delete(node),
  addToHitGrid(x:number,y:number,w:number,h:number,id:number){lib.addToHitGrid(native,x,y,w,h,id)},
  pushHitGridScissorRect(x:number,y:number,w:number,h:number){lib.hitGridPushScissorRect(native,x,y,w,h)},
  popHitGridScissorRect(){lib.hitGridPopScissorRect(native)},
  clearHitGridScissorRects(){lib.hitGridClearScissorRects(native)},
  hasSelection:false,getSelection:()=>null,currentFocusedRenderable:null,currentFocusedEditor:null,
  keyInput:keys,_internalKeyInput:keys,
  requestLive(){if(liveCount++===0){const tick=()=>{if(stopped||liveCount<=0)return;dirty=true;liveTimer=setTimeout(tick,16)};liveTimer=setTimeout(tick,16)}},
  dropLive(){liveCount=Math.max(0,liveCount-1);if(!liveCount)clearTimeout(liveTimer)},
});
const reconciler=ReactReconciler(hostConfig);
const report=(error:unknown)=>{throw error};
let effectMounted=false;
const mouse=new MouseRouter((x,y)=>x<0||y<0?undefined:Renderable.renderablesByNumber.get(lib.checkHit(native,x,y)));
function shutdown(){
  if(stopped)return;
  stopped=true;
  try {
    if(container){reconciler.updateContainerSync(null,container,null,null);reconciler.flushSyncWork();reconciler.flushPassiveEffects()}
  } finally {
    try { root?.destroyRecursively(); }
    finally {try{mouse.reset();if(native){lib.disableMouse(native);lib.destroyRenderer(native)}}finally{parser.destroy();lib?.dispose();__timers.clear()}}
  }
}
Object.assign(globalThis,{
  __shutdown:shutdown,
  __input(data:ArrayBuffer){reconciler.flushSyncFromReconciler(()=>{parser.push(new Uint8Array(data));drainInput()})},
  __resize(width:number,height:number){
    context.width=width;context.height=height;
    lib.resizeRenderer(native,width,height);
    root.width=width;root.height=height;
    context.emit("resize",width,height);dirty=true;
  },
  __tick(){__timers.tick()},
  __delay(){return __timers.delay()},
  __frame(){
    if(stopped||!dirty)return;
    dirty=false;context.frameId++;
    const buffer=lib.getNextBuffer(native);
    buffer.clear(RGBA.fromHex("#101820"));
    root.render(buffer,16);
    lib.render(native,false);
  },
  __inspect(){return JSON.stringify({effectMounted,keys:keys.listenerCount("key"),frame:context.frameId})},
  __snapshot(){return new TextDecoder().decode(lib.getCurrentBuffer(native).getRealCharBytes(true))},
});
export function mountDemo(App:()=>React.ReactNode,options:{onCaughtError?:(error:unknown)=>void}={}){
function Mounted(){
  useEffect(()=>{effectMounted=true;return()=>{effectMounted=false}},[]);
  return <App/>;
}
lib=resolveRenderLib();
native=lib.createRenderer(context.width,context.height,{bufferedOutput:__host.headless?"memory":"stdout",remote:false});
if(!native)throw new Error("Cannot create native terminal renderer");
// Detect multiplexers before setup emits the first graphics capability query.
for(const [key,value] of Object.entries(__host.env)) {
  if(!lib.setTerminalEnvVar(native,key,value))throw new Error(`Cannot forward terminal environment: ${key}`);
}
lib.setUseThread(native,false);
lib.setBackgroundColor(native,RGBA.fromHex("#101820"));
context.capabilities=lib.getTerminalCapabilities(native) as any;
if(!__host.headless)lib.setupTerminal(native,true);
if(!__host.headless)lib.enableMouse(native,true);
root=new RootRenderable(context as any);
container=reconciler.createContainer(root,1,null,false,null,"",report,options.onCaughtError??report,report,()=>{});
reconciler.updateContainerSync(<Mounted/>,container,null,null);
reconciler.flushSyncWork();
reconciler.flushPassiveEffects();


}
