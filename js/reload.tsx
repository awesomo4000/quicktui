import React,{useEffect,useState} from "../vendor/js/node_modules/react";
import {mountDemo,keys} from "./platform/demo";
import {getReloadState,getReloadInfo,requestReload} from "./app";
declare const __host:{generation:number,reloadState:string,reloadNotice:string,headless:boolean,tryPostMessage(text:string):string,requestReload(source?:string):void,quit():void};
const host=globalThis as any;
if(host.__reloadCanary!==undefined)throw Error("Previous runtime globals survived");
host.__reloadCanary=__host.generation;
const saved=getReloadState({count:0,round:0});
if(!Number.isInteger(saved.count)||!Number.isInteger(saved.round))throw Error("Invalid demo snapshot");
Object.assign(globalThis,{
  __reloadNotice:(notice:string)=>keys.emit("reload-notice",notice),
});
function App(){
  const [count,setCount]=useState(saved.count),[scratch,setScratch]=useState(0);
  const [notice,setNotice]=useState(getReloadInfo().notice||"Ready. Change both counters, then press R.");
  const [events,setEvents]=useState(0);
  useEffect(()=>{
    const key=(name:string)=>{
      if(name==="space"){saved.count++;setCount(saved.count)}
      if(name==="u")setScratch(n=>n+1);
      if(name==="r")requestReload();
      if(name==="b")requestReload("throw new Error('Deliberately broken replacement bundle');");
    };
    keys.on("key",key);keys.on("reload-notice",setNotice);
    host.__message=()=>setEvents(n=>n+1);
    return()=>{keys.off("key",key);keys.off("reload-notice",setNotice);delete host.__message};
  },[]);
  const accent=__host.generation%2?"#85ddca":"#d8b5ff";
  return <box width="100%" height="100%" border borderStyle="rounded" borderColor={accent} title=" 06b / Fresh runtime " padding={1} gap={1}>
    <text fg={accent}>Whole UI replacement · generation {__host.generation}</text>
    <text>Saved counter: {count}     Unsaved counter: {scratch}</text>
    <text fg="#c4ced4">Space changes saved · U changes unsaved · R replaces the runtime</text>
    <text fg="#c4ced4">B tries a broken bundle · Q exits</text>
    <box border borderColor={accent} padding={1} flexGrow={1} gap={1}>
      <text>06a keeps the runtime and loads component scripts into it.</text>
      <text>06b destroys QuickJS and React, then builds a fresh UI.</text>
      <text>Only the saved counter crosses as JSON. Module globals and unsaved state reset.</text>
      <text>The native renderer and worker remain alive. The last frame stays on screen.</text>
      <text>Native events received by this generation: {events}</text>
    </box>
    <text fg={accent}>{notice}</text>
    <text fg="#79909c">Experimental trusted reload · bundled source reused on R · no file watcher in 06b yet</text>
  </box>;
}
mountDemo(App,{exportState:()=>saved});
// One headless sequence spans eight fresh runtimes, including syntax/evaluation
// failure and a bounded infinite-loop candidate. This cannot be a Promise owned
// by the first runtime, because replacement intentionally destroys that Promise.
if(__host.headless){
  setTimeout(()=>{
    if(!host.__snapshot().includes("Unsaved counter: 0"))throw Error("Unsaved state survived replacement");
    keys.emit("key","u");
  },40);
  setTimeout(()=>{
    if(saved.count!==saved.round*7)throw Error("Reload lost snapshot");
    if(saved.round===3&&!__host.reloadNotice.includes("Replacement failed"))throw Error("Broken bundle was not recovered");
    if(saved.round===6&&!__host.reloadNotice.includes("Replacement failed"))throw Error("Timed-out bundle was not recovered");
    const text=host.__snapshot();
    if(!text.includes("Unsaved counter: 1")||!text.includes("06b"))throw Error("Fresh UI did not render");
    if(saved.round===8){__host.quit();return}
    saved.round++;saved.count+=7;
    if(saved.round===3)requestReload("const = ;");
    else if(saved.round===6)requestReload("while(true){}");
    else requestReload();
    if(__host.tryPostMessage("late")!=="closed")throw Error("Send crossed reload barrier");
  },100);
}
