import React, { useEffect, useState } from "../vendor/js/node_modules/react";
import ReactReconciler from "../vendor/js/node_modules/react-reconciler";
import { hostConfig } from "../vendor/opentui/packages/react/src/reconciler/host-config";
import { Renderable, RootRenderable } from "../vendor/opentui/packages/core/src/Renderable";
import { resolveRenderLib } from "../vendor/opentui/packages/core/src/zig";
import { RGBA } from "../vendor/opentui/packages/core/src/lib/RGBA";
import { EventEmitter } from "../vendor/js/node_modules/events";
import { StdinParser } from "../vendor/opentui/packages/core/src/lib/stdin-parser";
import { MouseRouter } from "./platform/mouse";

declare const __host: {width:number,height:number,headless:boolean,env:Record<string,string>,quit():void};
declare const __timers: {tick():void,delay():number,clear():void};
let dirty=true;
let stopped=false;
let container:any;
let native:any;
let root:RootRenderable;
let lib:ReturnType<typeof resolveRenderLib>;
const keys=new EventEmitter();
const parser=new StdinParser({onTimeoutFlush:()=>drainInput()});
function drainInput(){parser.drain(event=>{
  if(event.type==="key"){
    if((event.key.ctrl&&event.key.name==="c")||event.key.name.toLowerCase()==="q"){__host.quit();return}
    keys.emit("key",event.key.name.toLowerCase());
  } else if(event.type==="mouse"){
    mouse.dispatch(event.event);
  } else if(event.type==="response"&&native){
    lib.processCapabilityResponse(native,event.sequence);
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
  requestLive(){throw new Error("Live animation is not supported by the counter profile")},dropLive(){},
});
const reconciler=ReactReconciler(hostConfig);
const report=(error:unknown)=>{throw error};
let effectMounted=false;
const mouse=new MouseRouter((x,y)=>x<0||y<0?undefined:Renderable.renderablesByNumber.get(lib.checkHit(native,x,y)));
function App(){
  const [hover,setHover]=useState("none");
  const [clicks,setClicks]=useState([0,0,0]);
  const [wheel,setWheel]=useState(0);
  const [drag,setDrag]=useState("Drag inside this pad");
  const [last,setLast]=useState("Move the pointer into this pane");
  const [size,setSize]=useState([context.width,context.height]);
  useEffect(()=>{
    effectMounted=true;
    const resize=(w:number,h:number)=>setSize([w,h]);
    context.on("resize",resize);
    return ()=>{effectMounted=false;context.off("resize",resize)};
  },[]);
  return <box width="100%" height="100%" padding={1} backgroundColor="#101820"
    onMouse={(e:any)=>setLast(`${e.type} at ${e.x+1},${e.y+1} · button ${e.button}${e.modifiers.shift?" · shift":""}${e.modifiers.ctrl?" · ctrl":""}${e.modifiers.alt?" · alt":""}`)}>
    <box border borderStyle="rounded" borderColor="#63c7b2" title=" 02 / Mouse playground " padding={1} gap={0} width="100%">
      <text fg="#f6f0dd"><b>Point, click, drag, scroll</b></text>
      <text fg="#718b99">Example 01: dragon demo · launch without --mouse</text>
      <text fg="#c2ced5">Terminal {size[0]} × {size[1]} · Q exit</text>
      <box id="click-pad" border height={5} width="100%" paddingX={1}
        backgroundColor={hover==="click"?"#244c50":"#192932"} borderColor="#63c7b2"
        onMouseOver={()=>setHover("click")} onMouseOut={()=>setHover("none")}
        onMouseDown={(e:any)=>{if(e.button<3)setClicks(v=>v.map((n,i)=>n+(i===e.button?1:0)))}}>
        <text fg="#f6f0dd">Click pad · hover: {hover}</text>
        <text fg="#c2ced5">Left {clicks[0]} · Middle {clicks[1]} · Right {clicks[2]}</text>
      </box>
      <box id="drag-pad" border height={4} width="100%" paddingX={1} borderColor="#e9af70"
        onMouseDown={(e:any)=>setDrag(`Pressed at ${e.x+1},${e.y+1}`)}
        onMouseDrag={(e:any)=>setDrag(`Dragging at ${e.x+1},${e.y+1}`)}
        onMouseUp={(e:any)=>setDrag(`Released at ${e.x+1},${e.y+1}`)}>
        <text fg="#e9af70">{drag}</text>
        <text fg="#718b99">Hold a button and move. Release outside the pad too.</text>
      </box>
      <box id="wheel-pad" border height={3} width="100%" paddingX={1} borderColor="#a59de0"
        onMouseScroll={(e:any)=>setWheel(v=>v+((e.scroll.direction==="up"||e.scroll.direction==="left")?1:-1)*e.scroll.delta)}>
        <text fg="#a59de0">Wheel value: {wheel}</text>
      </box>
      <text fg="#63c7b2">{last}</text>
    </box>
  </box>;
}
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
    root.render(buffer,0);
    lib.render(native,false);
  },
  __inspect(){return JSON.stringify({effectMounted,keys:keys.listenerCount("key"),frame:context.frameId})},
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

// Exercise actual terminal bytes, React handlers, and native hit-grid geometry.
if(__host.headless)Object.assign(globalThis,{
  __selfTest(){
    const host=globalThis as any;
    const frame=()=>{reconciler.flushSyncWork();reconciler.flushPassiveEffects();host.__frame()};
    const expect=(text:string)=>{if(!host.__snapshot().includes(text))throw new Error(`Mouse snapshot missing ${text}: ${host.__snapshot()}`)};
    const feed=(text:string)=>{reconciler.flushSyncFromReconciler(()=>host.__input(new TextEncoder().encode(text).buffer));frame()};
    const point=(id:string)=>{const node=[...Renderable.renderablesByNumber.values()].find(n=>n.id===id)!;return [node.x+2,node.y+1]};
    const report=(code:number,x:number,y:number,release=false)=>`\x1b[<${code};${x+1};${y+1}${release?"m":"M"}`;
    frame();
    let [x,y]=point("click-pad");
    feed("\x1b[<35;");feed(`${x+1};${y+1}M`);expect("hover: click");
    for(let button=0;button<3;button++){feed(report(button,x,y));feed(report(button,x,y,true))}
    expect("Left 1 · Middle 1 · Right 1");
    feed(report(0,0,0));feed(report(0,0,0,true));expect("Left 1 · Middle 1 · Right 1");
    [x,y]=point("drag-pad");feed(report(0,x,y));feed(report(32,0,0));expect("Dragging at 1,1");
    feed(report(0,0,0,true));expect("Released at 1,1");
    [x,y]=point("wheel-pad");feed(report(64,x,y));expect("Wheel value: 1");feed(report(65,x,y));expect("Wheel value: 0");
    reconciler.flushSyncFromReconciler(()=>host.__resize(64,24));frame();
    [x,y]=point("click-pad");feed(report(0,x,y));feed(report(0,x,y,true));expect("Left 2");expect("Terminal 64 × 24");
  }
});
