import React, { useEffect, useState } from "../vendor/js/node_modules/react";
import ReactReconciler from "../vendor/js/node_modules/react-reconciler";
import { hostConfig } from "../vendor/opentui/packages/react/src/reconciler/host-config";
import { Renderable, RootRenderable } from "../vendor/opentui/packages/core/src/Renderable";
import { resolveRenderLib } from "../vendor/opentui/packages/core/src/zig";
import { RGBA } from "../vendor/opentui/packages/core/src/lib/RGBA";
import { EventEmitter } from "../vendor/js/node_modules/events";
import { StdinParser } from "../vendor/opentui/packages/core/src/lib/stdin-parser";
import { InternalKeyHandler, KeyEvent, PasteEvent } from "../vendor/opentui/packages/core/src/lib/KeyHandler";
import { Selection } from "../vendor/opentui/packages/core/src/lib/selection";
import { Gallery, pages, disposeGallery } from "./gallery-app";
import { MouseRouter } from "./platform/mouse";

declare const __host: {width:number,height:number,headless:boolean,env:Record<string,string>,quit():void};
declare const __timers: {tick():void,delay():number,clear():void};
let dirty=true;
let stopped=false;
let container:any;
let native:any;
let root:RootRenderable;
let lib:ReturnType<typeof resolveRenderLib>;
const keys=new InternalKeyHandler();
let selection:Selection|null=null;
let selectionOwner:Renderable|null=null;
let liveCount=0;
let liveTimer:any;
const parser=new StdinParser({onTimeoutFlush:()=>drainInput()});
function drainInput(){parser.drain(event=>{
  if(event.type==="key"){
    if(event.key.ctrl&&event.key.name==="c"){__host.quit();return}
    keys.emit(event.key.eventType==="release"?"keyrelease":"keypress",new KeyEvent(event.key));
  } else if(event.type==="paste"){
    keys.emit("paste",new PasteEvent(event.bytes));
  } else if(event.type==="mouse"){
    const raw=event.event;
    let target=hit(raw.x,raw.y);
    if(raw.type==="down"){
      let focus=target;
      while(focus&&!focus.focusable)focus=focus.parent as any;
      focus?.focus();
      if(raw.button===0&&target?.shouldStartSelection(raw.x,raw.y))context.startSelection(target,raw.x,raw.y);
    }
    if(selection?.isDragging&&(raw.type==="drag"||raw.type==="up"))context.updateSelection(target,raw.x,raw.y,{finishDragging:raw.type==="up"});
    mouse.dispatch(raw);
  } else if(event.type==="response"&&native){
    lib.processCapabilityResponse(native,event.sequence);
  }
})}
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
  keyInput:keys,_internalKeyInput:keys,
  requestLive(){if(liveCount++===0){const tick=()=>{if(stopped||liveCount<=0)return;dirty=true;liveTimer=setTimeout(tick,16)};liveTimer=setTimeout(tick,16)}},
  dropLive(){liveCount=Math.max(0,liveCount-1);if(!liveCount)clearTimeout(liveTimer)},
});
Object.defineProperty(context,"hasSelection",{get:()=>selection!==null});
const reconciler=ReactReconciler(hostConfig);
const report=(error:any)=>{console.error(String(error),error?.stack??"");throw error};
let effectMounted=false;
const hit=(x:number,y:number)=>x<0||y<0?undefined:Renderable.renderablesByNumber.get(lib.checkHit(native,x,y));
const mouse=new MouseRouter(hit);
let page=0;
let setPageState:(p:number)=>void;
function changePage(next:number){context.clearSelection();context.currentFocusedRenderable?.blur();mouse.reset();page=(next+pages.length)%pages.length;setPageState(page)}
function focusNext(reverse=false){
  const items=[...Renderable.renderablesByNumber.values()].filter(n=>n.focusable&&n.visible&&!n.isDestroyed);
  const current=items.indexOf(context.currentFocusedRenderable);
  items[(current+(reverse?-1:1)+items.length)%items.length]?.focus();
}
function App(){
  const [selected,setSelected]=useState(0);setPageState=setSelected;
  useEffect(()=>{
    effectMounted=true;
    const key=(e:KeyEvent)=>{
      if(e.name==="escape"){__host.quit();e.preventDefault();e.stopPropagation()}
      if(e.name==="f2"||e.name==="f1"){changePage(page+(e.name==="f2"?1:-1));e.preventDefault();e.stopPropagation()}
      if(e.name==="tab"){focusNext(e.shift);e.preventDefault();e.stopPropagation()}
    };
    keys.on("keypress",key);return ()=>{effectMounted=false;keys.off("keypress",key)};
  },[]);
  return <Gallery page={selected} changePage={changePage}/>;
}
function shutdown(){
  if(stopped)return;
  stopped=true;
  try {
    if(container){reconciler.updateContainerSync(null,container,null,null);reconciler.flushSyncWork();reconciler.flushPassiveEffects()}
  } finally {
    try { root?.destroyRecursively(); }
    finally {try{context.clearSelection();mouse.reset();disposeGallery();if(native){lib.disableMouse(native);lib.destroyRenderer(native)}}finally{parser.destroy();lib?.dispose();__timers.clear()}}
  }
}
Object.assign(globalThis,{
  __shutdown:shutdown,
  __input(data:ArrayBuffer){parser.push(new Uint8Array(data));drainInput()},
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
  __inspect(){return JSON.stringify({effectMounted,keys:keys.listenerCount("keypress"),frame:context.frameId})},
  __snapshot(){return new TextDecoder().decode(lib.getCurrentBuffer(native).getRealCharBytes(true))},
});
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
container=reconciler.createContainer(root,1,null,false,null,"",report,report,report,()=>{});
reconciler.updateContainerSync(<App/>,container,null,null);
reconciler.flushSyncWork();
reconciler.flushPassiveEffects();


if(__host.headless)Object.assign(globalThis,{
  async __selfTest(){
    const host=globalThis as any;
    const frame=()=>{reconciler.flushSyncWork();reconciler.flushPassiveEffects();host.__frame()};
    const sync=(fn:()=>void)=>{reconciler.flushSyncFromReconciler(fn);frame()};
    const expect=(text:string)=>{if(!host.__snapshot().includes(text))throw new Error(`Gallery snapshot missing ${text}: ${host.__snapshot()}`)};
    const feed=(text:string)=>sync(()=>host.__input(new TextEncoder().encode(text).buffer));
    const node=(id:string)=>{const n=[...Renderable.renderablesByNumber.values()].find(n=>n.id===id);if(!n)throw new Error(`Missing ${id}`);return n as any};
    const visit=(p:number)=>{sync(()=>changePage(p));frame()};
    sync(()=>host.__resize(96,34));frame();expect("Unicode:");
    for(let i=0;i<pages.length;i++){visit(i);expect(pages[i]);console.log(`Gallery mounted ${pages[i]}`)}
    visit(1);sync(()=>node("gallery-input").focus());feed("Ember");expect("Name: Ember");feed("\r");expect("Submitted: Ember");
    feed("\x1b[200~ the dragon\x1b[201~");expect("Name: Ember the dragon");
    feed("\x7f");expect("Name: Ember the drago");
    feed("\x1b[1;2D");feed("X");expect("Name: Ember the dragX");
    feed("\t");feed("Wings\rTwo");if(!node("gallery-textarea").plainText.includes("Wings\nTwo"))throw new Error("Textarea typing or focus traversal failed");
    visit(2);sync(()=>node("gallery-select").focus());feed("\x1b[B\r");expect("Chosen: Nimbus");feed("\t\x1b[C");expect("Active tab: Food");
    visit(3);const scroller=node("gallery-scroll");const x=scroller.x+2,y=scroller.y+2;
    feed(`\x1b[<65;${x+1};${y+1}M`.repeat(8));frame();if(scroller.scrollTop<=0)throw new Error("Scrollbox wheel did not scroll");
    const slider=node("gallery-slider");const sx=slider.x+slider.width-2,sy=slider.y;
    feed(`\x1b[<0;${sx+1};${sy+1}M\x1b[<0;${sx+1};${sy+1}m`);if(slider.value<=25)throw new Error("Slider click did not move");
    visit(5);expect("const dragon");
    visit(6);expect("wings");const toggle=node("gallery-diff-toggle");feed(`\x1b[<0;${toggle.x+1};${toggle.y+1}M\x1b[<0;${toggle.x+1};${toggle.y+1}m`);expect("split");
    visit(7);for(let i=0;i<12;i++){await Promise.resolve();frame()}expect("Dragon field guide");expect("Nimbus");if(host.__snapshot().includes("**Ember**")||host.__snapshot().includes("# Dragon"))throw new Error("Markdown markers were not concealed");
    // Repeated mounts at a smaller terminal exercise stale focus/hit targets and teardown.
    sync(()=>host.__resize(72,28));for(let i=0;i<pages.length;i++)visit(i);
    visit(0);frame();
  }
});
