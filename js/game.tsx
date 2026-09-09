import React,{useEffect,useState} from "../vendor/js/node_modules/react";
import {mountApp} from "./platform/demo";
import {useKeyboardEvents,HeldKeys,type AppKeyEvent,type KeyboardCapabilities,quit} from "./app";
import {PlatformGame,WORLD,FLOOR} from "./game-model";
declare const __host:{headless:boolean,example:string};
const diagnostic=__host.example==="keyboard";
const game=new PlatformGame();
let redraw=()=>{};
let status="startup",caps:KeyboardCapabilities={requestedFlags:31,protocol:"unknown",releases:"unknown",focus:"unknown",modifierEvents:"unknown",heldStateAvailable:false};
const tracker=new HeldKeys(e=>{status=e.reason;paused=true;redraw()});
const recent:AppKeyEvent[]=[],latencies:number[]=[];
let pendingJump=false,tap=0,paused=false;
function input(event:AppKeyEvent){
 recent.push(event);if(recent.length>8)recent.shift();
 latencies.push(event.dispatchedAt-event.receivedAt);if(latencies.length>256)latencies.shift();
 if(event.kind!=="release"&&event.ctrl&&event.name==="c"){quit();return true}
 if(event.kind==="press"&&event.name==="r"){game.reset();tracker.reset();paused=false;return true}
 if(event.kind==="press")paused=false;
 if(caps.heldStateAvailable&&event.trackable)tracker.update(event);
 else if(event.kind==="press"){
  if(event.name==="left"||event.name==="a")tap=-1;
  if(event.name==="right"||event.name==="d")tap=1;
  if(event.name==="w"||event.name==="space"||event.name==="up")pendingJump=true;
 }
 redraw();return true;
}
function stats(){const a=[...latencies].sort((a,b)=>a-b),q=(p:number)=>(a[Math.min(a.length-1,Math.floor(a.length*p))]??0).toFixed(2);return `local read→dispatch ms p95 ${q(.95)} p99 ${q(.99)} max ${q(1)} · n=${a.length}`}
function App(){
 useKeyboardEvents(input,{realtime:true,onReset(event){tracker.reset(event.reason);pendingJump=false;tap=0;paused=true;redraw()}});
 const [,setFrame]=useState(0);
 useEffect(()=>{redraw=()=>setFrame(n=>n+1);const timer=setInterval(()=>{
  const edges=tracker.drainEdges();
  const jump=pendingJump||edges.some(e=>e.kind==="press"&&(e.name==="w"||e.name==="space"||e.name==="up"));
  const release=edges.some(e=>e.kind==="release"&&(e.name==="w"||e.name==="space"||e.name==="up"));
  const direction=Number(tracker.has("right")||tracker.has("d"))-Number(tracker.has("left")||tracker.has("a"));
  if(!paused)game.step(1/60,direction||tap,jump,release);
  pendingJump=false;tap=0;redraw();
 },1000/60);return()=>{clearInterval(timer);redraw=()=>{}}},[]);
 const tiles=[];for(let y=0;y<14;y++)for(let x=0;x<WORLD;x++)if(game.solid(x,y))tiles.push(<text key={`${x}:${y}`} position="absolute" left={x} top={y} fg={y===FLOOR?"#83df99":"#74669e"}>{y===FLOOR?"▀":"█"}</text>);
 return <box border borderColor="#ad90e8" title={diagnostic?" 09 / Keyboard laboratory ":" 08 / Tiny crossing "} padding={1} gap={1} height="100%">
  <text fg="#f5cb87">{diagnostic?"What the terminal actually sends":"Get to the flag. Mind the gaps."}</text>
  <text>{caps.heldStateAvailable?"Release observed · held controls for protocol keys, taps for legacy keys":"Tap-to-step · press and release a key to test release support"}</text>
  <text fg="#90a6b8">A/D move · W jump · arrows/Space also work · R restart · Ctrl+C exit</text>
  {!diagnostic&&<box width={WORLD} height={14} backgroundColor="#142036" flexShrink={0}>
   {tiles}<text position="absolute" left={37} top={11} fg="#f88484">▲</text>
   <text position="absolute" left={61} top={10} fg="#f5cb87">⚑</text>
   <text position="absolute" left={Math.floor(game.x)} top={Math.min(13,Math.floor(game.y))} fg="#83eff0">@</text>
  </box>}
  <text>{game.won?"EXIT REACHED! R to play again":`x=${game.x.toFixed(1)} y=${game.y.toFixed(1)} grounded=${game.grounded} deaths=${game.deaths}`}</text>
  <text>Held: {[...tracker.held].join(" ")||"none"} · reset: {status} {paused?"· paused until fresh press":""}</text>
  <text>Requested flags {caps.requestedFlags} · protocol {caps.protocol} · releases {caps.releases} · focus {caps.focus}</text>
  <text fg="#90a6b8">{stats()}</text>
  {diagnostic&&recent.map(e=><text key={e.sequenceNumber}>{e.sequenceNumber} {e.kind} {e.identity} {e.name} ctrl={String(e.ctrl)} alt={String(e.option)} super={String(e.super)} text={JSON.stringify(e.text)} raw={JSON.stringify(e.raw)}</text>)}
 </box>;
}
mountApp(App,{keyboard:{mode:"realtime"},
 onKeyboardCapabilities(value){if(!caps.heldStateAvailable&&value.heldStateAvailable)tracker.reset();caps=value;redraw()},
 onInputReset(event){tracker.reset(event.reason);pendingJump=false;tap=0;paused=true;redraw()},
});
if(__host.headless)Object.assign(globalThis,{async __selfTest(){
 const h=globalThis as any,feed=(s:string)=>h.__input(new TextEncoder().encode(s).buffer);
 feed("\x1b[100;1:1u\x1b[100;1:3u");
 if(!caps.heldStateAvailable)throw Error("Release capability not observed");
 feed("a");if(tap!==-1)throw Error("Legacy movement lost after protocol release");
 feed("w");if(!pendingJump)throw Error("Legacy jump lost after protocol release");
 pendingJump=false;tap=0;
 feed("\x1b[100;1:1u\x1b[32;1:1u\x1b[32;1:3u");
 if(!tracker.has("d")||tracker.has("space"))throw Error("Overlapping keys lost");
 feed("\x1b[O");if(tracker.held.size||!paused)throw Error("Focus reset failed");
 feed("\x1b[200~dddd q\n \x1b[201~");if(tracker.held.size)throw Error("Paste became keys");
 h.__frame();if(!h.__snapshot().includes(diagnostic?"Keyboard laboratory":"Tiny crossing"))throw Error("Demo missing");
}});
