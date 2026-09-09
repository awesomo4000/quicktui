import {AppKeyEvent,dispatchAppKey,resetKeyboardSubscriptions,keyboardFlags,type KeyboardOptions,type KeyboardCapabilities,type InputReset} from "../keyboard";
import {KeyEvent,PasteEvent} from "../../vendor/opentui/packages/core/src/lib/KeyHandler";
import {Selection} from "../../vendor/opentui/packages/core/src/lib/selection";
import React, { useEffect } from "../../vendor/js/node_modules/react";
import ReactReconciler from "../../vendor/js/node_modules/react-reconciler";
import { hostConfig } from "../../vendor/opentui/packages/react/src/reconciler/host-config";
import { Renderable, RootRenderable } from "../../vendor/opentui/packages/core/src/Renderable";
import { resolveRenderLib } from "../../vendor/opentui/packages/core/src/zig";
import { RGBA } from "../../vendor/opentui/packages/core/src/lib/RGBA";
import { EventEmitter } from "../../vendor/js/node_modules/events";
import { StdinParser } from "../../vendor/opentui/packages/core/src/lib/stdin-parser";
import { MouseRouter } from "./mouse";

declare const __host: {width:number,height:number,headless:boolean,env:Record<string,string>,borrowRenderer():number,presentFrame():void,canDispatch():boolean,configureKeyboard(flags:number):void,generation?:number,now():number,quit():void};
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
// OSC 52 writes to the terminal clipboard; success means the sequence was sent.
export function copyTerminalText(text:string){
  try{return lib.copyToClipboardOSC52(native,0,new TextEncoder().encode(text))}
  catch{return false}
}
let keyInterceptor:((key:any)=>boolean)|null=null;
export function interceptKeys(handler:((key:any)=>boolean)|null){keyInterceptor=handler}
export const graphicsState={confirmed:false};
export interface AppOptions {
  keyboard?:KeyboardOptions;
  onInputReset?:(event:InputReset)=>void;
  onKeyboardCapabilities?:(capabilities:KeyboardCapabilities)=>void;
  exportState?:()=>unknown;
  onFirstLayout?:()=>void;
  onReloadError?:(notice:string)=>void;
  onCaughtError?:(error:unknown)=>void;
  onKey?:(key:AppKeyEvent)=>boolean|void;
  onPaste?:(text:string)=>void;
  onPasteRejected?:()=>void;
  onMessage?:(message:string)=>void;
  onDisconnect?:(reason:string)=>void;
}
let appOptions:AppOptions={};
let firstLayout=true;
let inputSequence=0,receivedAt=0,inputOverflow=false;
let keyboard:KeyboardCapabilities={requestedFlags:5,protocol:"unknown",releases:"unknown",focus:"unknown",modifierEvents:"unknown",heldStateAvailable:false};
const reportKeyboard=()=>appOptions.onKeyboardCapabilities?.({...keyboard});
const resetInput=(reason:InputReset["reason"])=>{
 try{appOptions.onInputReset?.({reason})}finally{resetKeyboardSubscriptions({reason})}
};
let demoShortcuts=false;
const parser=new StdinParser({onInputOverflow:()=>{inputOverflow=true},onTimeoutFlush:()=>drainInput(),onPasteRejected:()=>appOptions.onPasteRejected?.()});
function drainInput(){parser.drain(event=>{
  if(!__host.canDispatch())return;
  if(event.type==="key"){
    if(keyInterceptor?.(event.key))return;
    const key=new AppKeyEvent(event.key,receivedAt,++inputSequence,__host.now());
    const previous=JSON.stringify(keyboard);
    if(key.source==="kitty")keyboard.protocol="kitty";
    else if(keyboard.protocol==="unknown")keyboard.protocol="legacy";
    if(key.kind==="release"&&key.source==="kitty"){keyboard.releases="observed";keyboard.heldStateAvailable=true;}
    if(/^(left_|right_)?(shift|control|alt|super|hyper|meta)$/.test(key.name)&&key.source==="kitty")keyboard.modifierEvents="observed";
    if(previous!==JSON.stringify(keyboard))reportKeyboard();
    if(!demoShortcuts){dispatchAppKey(key,appOptions.onKey,(name,event)=>keys.emit(name,event));return;}
    if(appOptions.onKey?.(key)||key.defaultPrevented)return;
    if(key.kind==="release")return;
    if((event.key.ctrl&&event.key.name==="c")||event.key.name.toLowerCase()==="q"){__host.quit();return}
    keys.emit("key",event.key.name.toLowerCase());
  } else if(event.type==="paste"){
    if(appOptions.onPaste)appOptions.onPaste(new TextDecoder().decode(event.bytes));
    else keys.emit("paste",demoShortcuts?event:new PasteEvent(event.bytes,event.metadata));
  } else if(event.type==="mouse"){
    mouse.dispatch(event.event);
  } else if(event.type==="response"&&native){
    if(event.sequence==="\x1b[I"||event.sequence==="\x1b[O"){
      keyboard.focus="observed";reportKeyboard();
      if(event.sequence==="\x1b[O")resetInput("focus-loss");
      return;
    }
    lib.processCapabilityResponse(native,event.sequence);
    context.capabilities=lib.getTerminalCapabilities(native) as any;
    const reply=event.sequence.match(/^\x1b_G([^;]*);([\s\S]*?)\x1b\\$/);
    if(reply&&reply[1].split(",").includes("i=31337")&&reply[2]==="OK"){
      graphicsState.confirmed=true;keys.emit("graphics",true);dirty=true;
    }
  }
})}
let selection:Selection|null=null,selectionOwner:Renderable|null=null;
const lifecycle=new Set<any>();
const context:any=Object.assign(new EventEmitter(),{
  width:__host.width,height:__host.height,frameId:0,widthMethod:"unicode",capabilities:null,
  requestRender(){dirty=true},getLifecyclePasses:()=>lifecycle,
  registerLifecyclePass:(node:any)=>lifecycle.add(node),unregisterLifecyclePass:(node:any)=>lifecycle.delete(node),
  addToHitGrid(x:number,y:number,w:number,h:number,id:number){lib.addToHitGrid(native,x,y,w,h,id)},
  pushHitGridScissorRect(x:number,y:number,w:number,h:number){lib.hitGridPushScissorRect(native,x,y,w,h)},
  popHitGridScissorRect(){lib.hitGridPopScissorRect(native)},
  clearHitGridScissorRects(){lib.hitGridClearScissorRects(native)},
  getSelection:()=>selection,currentFocusedRenderable:null,currentFocusedEditor:null,
  focusRenderable(node:Renderable){
    const old=context.currentFocusedRenderable;
    if(old&&old!==node)old.blur();
    context.currentFocusedRenderable=node;
  },
  blurRenderable(node:Renderable){if(context.currentFocusedRenderable===node)context.currentFocusedRenderable=null},
  setCursorPosition(x:number,y:number,visible:boolean){lib.setCursorPosition(native,x,y,visible)},
  setCursorStyle(style:any){lib.setCursorStyleOptions(native,style)},
  clearSelection(){const old=selectionOwner;selection=null;selectionOwner=null;if(old&&!old.isDestroyed)old.onSelectionChanged(null);context.emit("selection",null)},
  startSelection(node:Renderable,x:number,y:number){
    context.clearSelection();selectionOwner=node;selection=new Selection(node,{x,y},{x,y});selection.isStart=true;
    node.onSelectionChanged(selection);
  },
  updateSelection(_node:any,x:number,y:number,options:any={}){
    if(selection&&selectionOwner&&!selectionOwner.isDestroyed){selection.isStart=false;selection.focus={x,y};selection.isDragging=!options.finishDragging;selectionOwner.onSelectionChanged(selection);context.emit("selection",selection)}
  },
  requestSelectionUpdate(){if(selection&&selectionOwner&&!selectionOwner.isDestroyed)selectionOwner.onSelectionChanged(selection)},
  keyInput:keys,_internalKeyInput:{onInternal:(name:string,handler:any)=>keys.on(name,handler),offInternal:(name:string,handler:any)=>keys.off(name,handler)},
  requestLive(){if(liveCount++===0){const tick=()=>{if(stopped||liveCount<=0)return;dirty=true;liveTimer=setTimeout(tick,16)};liveTimer=setTimeout(tick,16)}},
  dropLive(){liveCount=Math.max(0,liveCount-1);if(!liveCount)clearTimeout(liveTimer)},
});
Object.defineProperty(context,"hasSelection",{get:()=>selection!==null});
const reconciler=ReactReconciler(hostConfig);
const report=(error:unknown)=>{throw error};
let effectMounted=false;
const mouse=new MouseRouter((x,y)=>x<0||y<0?undefined:Renderable.renderablesByNumber.get(lib.checkHit(native,x,y)));
function shutdown(){
  if(stopped)return;
  stopped=true;
  try {
    try{resetInput("shutdown")}finally{
    if(container){reconciler.updateContainerSync(null,container,null,null);reconciler.flushSyncWork();reconciler.flushPassiveEffects()}
    }
  } finally {
    try { root?.destroyRecursively(); }
    finally {try{context.clearSelection();mouse.reset();native=null}finally{parser.destroy();lib?.dispose();__timers.clear()}}
  }
}
Object.assign(globalThis,{
  __shutdown:shutdown,
  __inputReset:(reason:InputReset["reason"])=>resetInput(reason),
  __inputReadyForReload:()=>parser.readyForReload,
  __input(data:ArrayBuffer,time=__host.now()){receivedAt=time;reconciler.flushSyncFromReconciler(()=>{parser.push(new Uint8Array(data));drainInput();if(inputOverflow){inputOverflow=false;resetInput("overflow")}})},
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
    if(firstLayout){
      firstLayout=false;
      if(appOptions.onFirstLayout){
        appOptions.onFirstLayout();
        buffer.clear(RGBA.fromHex("#101820"));root.render(buffer,16);
      }
    }
    __host.presentFrame();
  },
  __inspect(){return JSON.stringify({effectMounted,keys:keys.listenerCount("key"),frame:context.frameId})},
  __snapshot(){return new TextDecoder().decode(lib.getCurrentBuffer(native).getRealCharBytes(true))},
});
export function mountDemo(App:()=>React.ReactNode,options:AppOptions={}){
  demoShortcuts=true;
  return mountApp(App,options);
}
export function mountApp(App:()=>React.ReactNode,options:AppOptions={}){
if(container||stopped)throw new Error("Only one application mount per runtime is supported");
appOptions=options;
keyboard.requestedFlags=keyboardFlags(options.keyboard);
__host.configureKeyboard(keyboard.requestedFlags);
parser.updateProtocolContext({kittyKeyboardEnabled:keyboard.requestedFlags!==0});
reportKeyboard();
resetInput((__host.generation??1)>1?"reload":"startup");
if(options.exportState)Object.assign(globalThis,{__exportState:()=>{
  const text=JSON.stringify(options.exportState!());
  if(text===undefined)throw new Error("exportState must return JSON-serializable data");
  return text;
}});
if(options.onReloadError)Object.assign(globalThis,{__reloadNotice:options.onReloadError});
if(options.onMessage)Object.assign(globalThis,{__message:options.onMessage});
Object.assign(globalThis,{__endpointClosed:(reason:string)=>{resetInput("endpoint-closed");options.onDisconnect?.(reason)}});
function Mounted(){
  useEffect(()=>{effectMounted=true;return()=>{effectMounted=false}},[]);
  return <App/>;
}
lib=resolveRenderLib();
native=__host.borrowRenderer();
lib.setBackgroundColor(native,RGBA.fromHex("#101820"));
context.capabilities=lib.getTerminalCapabilities(native) as any;
root=new RootRenderable(context as any);
container=reconciler.createContainer(root,1,null,false,null,"",report,options.onCaughtError??report,report,()=>{});
reconciler.updateContainerSync(<Mounted/>,container,null,null);
reconciler.flushSyncWork();
reconciler.flushPassiveEffects();
return {quit:()=>__host.quit(),snapshot:()=>new TextDecoder().decode(lib.getCurrentBuffer(native).getRealCharBytes(true))};
}
