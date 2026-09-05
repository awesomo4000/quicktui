import { Buffer } from "buffer";
import React, { useEffect, useState } from "../vendor/js/node_modules/react";
import ReactReconciler from "../vendor/js/node_modules/react-reconciler";
import { hostConfig } from "../vendor/opentui/packages/react/src/reconciler/host-config";
import { RootRenderable } from "../vendor/opentui/packages/core/src/Renderable";
import { resolveRenderLib } from "../vendor/opentui/packages/core/src/zig";
import { RGBA } from "../vendor/opentui/packages/core/src/lib/RGBA";
import { EventEmitter } from "../vendor/js/node_modules/events";
import { StdinParser } from "../vendor/opentui/packages/core/src/lib/stdin-parser";
import { NativeImage } from "../vendor/opentui/packages/core/src/image";

declare const __SPRITE_FRAMES_BASE64__:string[];
declare const __DEMO_PICTURE_BASE64__:string;
declare const __host: {width:number,height:number,headless:boolean,env:Record<string,string>,quit():void};
declare const __timers: {tick():void,delay():number,clear():void};
let dirty=true;
let stopped=false;
let container:any;
let native:any;
let root:RootRenderable;
let lib:ReturnType<typeof resolveRenderLib>;
let sampleImage:NativeImage;
const spriteFrames:NativeImage[]=[];
let graphicsStatus="Checking graphics support…";
let graphicsConfirmed=false;
let probeFinished=false;
function updateGraphics(status:string,confirmed=false){
  graphicsStatus=status;graphicsConfirmed=confirmed;
  context.emit("graphics");dirty=true;
}
const keys=new EventEmitter();
const parser=new StdinParser({onTimeoutFlush:()=>drainInput()});
function drainInput(){parser.drain(event=>{
  if(event.type==="key"){
    if((event.key.ctrl&&event.key.name==="c")||event.key.name.toLowerCase()==="q"){__host.quit();return}
    keys.emit("key",event.key.name.toLowerCase());
  } else if(event.type==="response"&&native){
    lib.processCapabilityResponse(native,event.sequence);
    context.capabilities=lib.getTerminalCapabilities(native) as any;
    const reply=event.sequence.match(/^\x1b_G([^;]*);([\s\S]*?)\x1b\\$/);
    if(reply&&reply[1].split(",").includes("i=31337")&&!probeFinished){
      probeFinished=true;
      updateGraphics(reply[2]==="OK"?"Kitty graphics confirmed":"Graphics query rejected · block fallback",reply[2]==="OK");
    }
  }
})}
const lifecycle=new Set<any>();
const context=Object.assign(new EventEmitter(),{
  width:__host.width,height:__host.height,frameId:0,widthMethod:"unicode",capabilities:null,
  requestRender(){dirty=true},getLifecyclePasses:()=>lifecycle,
  registerLifecyclePass:(node:any)=>lifecycle.add(node),unregisterLifecyclePass:(node:any)=>lifecycle.delete(node),
  addToHitGrid(){},pushHitGridScissorRect(){},popHitGridScissorRect(){},clearHitGridScissorRects(){},
  hasSelection:false,getSelection:()=>null,currentFocusedRenderable:null,currentFocusedEditor:null,
  keyInput:keys,_internalKeyInput:keys,
  requestLive(){throw new Error("Live animation is not supported by the counter profile")},dropLive(){},
});
const reconciler=ReactReconciler(hostConfig);
const report=(error:unknown)=>{throw error};
let effectMounted=false;
function App() {
  const [count,setCount]=useState(0);
  const [spriteFrame,setSpriteFrame]=useState(0);
  const [playing,setPlaying]=useState(true);
  useEffect(()=>{
    if(__host.headless||!playing)return;
    let timer:ReturnType<typeof setTimeout>;
    const next=()=>{setSpriteFrame(frame=>(frame+1)%spriteFrames.length);timer=setTimeout(next,125)};
    timer=setTimeout(next,125);
    return ()=>clearTimeout(timer);
  },[playing]);
  const [size,setSize]=useState([context.width,context.height]);
  const [graphics,setGraphics]=useState({status:graphicsStatus,confirmed:graphicsConfirmed});
  useEffect(()=>{
    effectMounted=true;
    const key=(name:string)=>{
      if(name==="space" || name==="up" || name==="+")setCount(v=>v+1);
      if(name==="down" || name==="-")setCount(v=>v-1);
      if(name==="r")setCount(0);
      if(name==="p")setPlaying(value=>!value);
      if(name==="n")setSpriteFrame(frame=>(frame+1)%spriteFrames.length);
    };
    const resize=(width:number,height:number)=>setSize([width,height]);
    const graphicsChanged=()=>setGraphics({status:graphicsStatus,confirmed:graphicsConfirmed});
    keys.on("key",key);context.on("resize",resize);
    context.on("graphics",graphicsChanged);
    return ()=>{effectMounted=false;keys.off("key",key);context.off("resize",resize);context.off("graphics",graphicsChanged)};
  },[]);
  return <box width="100%" height="100%" padding={1} backgroundColor="#101820">
    <box border borderStyle="rounded" borderColor="#63c7b2" title=" QuickTUI " padding={1} flexDirection="column" gap={1} width="100%">
      <text fg="#63c7b2"><b>React + QuickJS + Zig</b></text>
      <text fg="#f6f0dd">Count: {count}</text>
      <text fg="#c2ced5">Space / ↑  increment    ↓ / -  decrement    R  reset</text>
      <text fg="#c2ced5">Q exit · P play/pause · N next frame</text>
      <text fg="#718b99">Terminal {size[0]} × {size[1]} · native OpenTUI + Yoga</text>
      <text fg="#718b99">Unicode: café · é · 日本語 · 👩‍💻</text>
      <text fg="#63c7b2">{graphics.status}</text>
      <box flexDirection="row" justifyContent="space-between" width="100%">
      <image source={sampleImage} width={40} height={Math.max(8,size[1]-22)} protocol={graphics.confirmed?"kitty":"blocks"} onError={report}/>
      <box flexDirection="column" alignItems="center" width={36}>
        <image source={spriteFrames[spriteFrame]} width={32} height={Math.max(6,size[1]-24)} protocol={graphics.confirmed?"kitty":"blocks"} onError={report}/>
        <text fg="#718b99">Wing cycle · {spriteFrame+1}/8 {playing?"":"paused"}</text>
      </box>
      </box>
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
    finally {try{sampleImage?.dispose();for(const frame of spriteFrames)frame.dispose();if(native)lib.destroyRenderer(native)}finally{parser.destroy();lib?.dispose();__timers.clear()}}
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
  __inspect(){return JSON.stringify({effectMounted,keys:keys.listenerCount("key"),frame:context.frameId,graphicsConfirmed,graphicsStatus})},
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
// Decode the vendored dragon photo embedded by the bundler. No runtime file access.
sampleImage=NativeImage.decode(Buffer.from(__DEMO_PICTURE_BASE64__,"base64"));
for(const encoded of __SPRITE_FRAMES_BASE64__)spriteFrames.push(NativeImage.fromRgba(Buffer.from(encoded,"base64"),176,208));
setTimeout(()=>{
  if(!probeFinished){probeFinished=true;updateGraphics("No graphics reply · block fallback")}
},2000);
root=new RootRenderable(context as any);
container=reconciler.createContainer(root,1,null,false,null,"",report,report,report,()=>{});
reconciler.updateContainerSync(<App/>,container,null,null);
reconciler.flushSyncWork();
reconciler.flushPassiveEffects();
