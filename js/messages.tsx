import React, {useEffect, useState, useRef} from "../vendor/js/node_modules/react";
import {Renderable} from "../vendor/opentui/packages/core/src/Renderable";
import {mountDemo, keys} from "./platform/demo";

declare const __host:{postMessage(message:string):boolean,headless:boolean};
type Reply={id:number,type:"progress"|"done",progress:number,atMs:number};
type Job={id:number,progress:number,status:string};
const listeners=new Set<(event:Reply)=>void>();
const received:Reply[]=[];
const acceptedIds:number[]=[];
let nextId=1;
let sent=0,rejected=0,uiTicks=0;
// The host invokes this on the JS/UI thread, after draining the native queue.
Object.assign(globalThis,{__message(message:string){
  const event:Reply=JSON.parse(message);
  if(__host.headless)received.push(event);
  for(const listener of listeners)listener(event);
}});
const barStyles=["solid","segmented","thin"] as const;
function ProgressBar({progress,style}:{progress:number,style:number}){
  const [width,setWidth]=useState(0);
  const filled=Math.round(width*progress/100);
  const color=progress===100?"#63c7b2":"#438b80";
  return <box flexGrow={1} minWidth={0} height={1}
    backgroundColor={style===0?"#243740":"#101820"}
    onSizeChange={function(this:{width:number}){setWidth(Math.max(0,Math.floor(this.width)))}}>
    {style===0?<box width={`${progress}%`} height={1} backgroundColor={color}/>:
      <text width="100%" height={1} fg={color}>{(style===1?"▰":"━").repeat(filled)}<span fg="#36535f">{(style===1?"·":"─").repeat(Math.max(0,width-filled))}</span></text>}
  </box>;
}
function App(){
  const [barStyle,setBarStyle]=useState(0);
  const [jobs,setJobs]=useState<Job[]>([]);
  const [tick,setTick]=useState(0);
  const [paused,setPaused]=useState(false);
  const [clicks,setClicks]=useState(0);
  const [counts,setCounts]=useState([0,0]);
  const [events,setEvents]=useState<Reply[]>([]);
  const finished=useRef(new Set<number>());
  function clearFinished(){
    const ids=new Set(finished.current);
    finished.current.clear();
    setJobs(rows=>rows.filter(row=>!ids.has(row.id)));
    setEvents(rows=>rows.filter(event=>!ids.has(event.id)));
  }
  function submit(count=1){
    for(let i=0;i<count;i++){
      const id=nextId++;
      // A false return is backpressure: keep the UI responsive and report it.
      if(__host.postMessage(String(id))){
        sent++;if(__host.headless)acceptedIds.push(id);setJobs(rows=>[...rows,{id,progress:0,status:"queued"}]);
      }else rejected++;
    }
    setCounts([sent,rejected]);
  }
  function spread(mode="spread"){
    const first=nextId;nextId+=10;
    // One atomic batch admits all ten logical requests, or rejects all ten.
    if(__host.postMessage(`${mode}:${first}`)){
      sent+=10;
      const rows=Array.from({length:10},(_,i)=>({id:first+i,progress:0,status:"queued"}));
      if(__host.headless)acceptedIds.push(...rows.map(row=>row.id));
      setJobs(previous=>[...previous,...rows]);
    }else rejected+=10;
    setCounts([sent,rejected]);
  }
  useEffect(()=>{
    const listener=(event:Reply)=>{
      if(event.type==="done")finished.current.add(event.id);
      setJobs(rows=>rows.map(row=>row.id===event.id?{...row,progress:event.progress,status:event.type==="done"?"done":"working"}:row));
      setEvents(rows=>[...rows,event]);
    };
    const key=(name:string)=>{if(name==="c")clearFinished();if(name==="v")setBarStyle(value=>(value+1)%barStyles.length);if(name==="p")setPaused(value=>!value);if(name==="s")submit();if(name==="b")submit(12);if(name==="f")spread();if(name==="r")spread("random");if(name==="space")setClicks(n=>n+1)};
    listeners.add(listener);keys.on("key",key);
    return()=>{listeners.delete(listener);keys.off("key",key)};
  },[]);
  useEffect(()=>{
    if(paused)return;
    const timer=setInterval(()=>{uiTicks++;setTick(uiTicks)},100);
    return()=>clearInterval(timer);
  },[paused]);
  return <box width="100%" height="100%" padding={1} backgroundColor="#101820">
    <box border borderStyle="rounded" borderColor="#63c7b2" title=" 04 / Native messages " paddingX={1} width="100%" height="100%" gap={1}>
      <text height={1} flexShrink={0} fg="#f6f0dd"><b>React → command queue → Zig worker → event queue → React</b></text>
      <text height={1} flexShrink={0} fg="#718b99">One worker thread · 256 queued commands · 16 queued replies · copied strings</text>
      <box flexDirection="row" height={1} flexShrink={0} gap={1}>
        <box flexShrink={0} backgroundColor="#294650" paddingX={1} onMouseDown={()=>submit()}><text fg="#63c7b2">S Job</text></box>
        <box flexShrink={0} backgroundColor="#294650" paddingX={1} onMouseDown={()=>submit(12)}><text fg="#63c7b2">B Burst</text></box>
        <box flexShrink={0} backgroundColor="#294650" paddingX={1} onMouseDown={()=>spread()}><text fg="#63c7b2">F Spread</text></box>
        <box flexShrink={0} backgroundColor="#294650" paddingX={1} onMouseDown={()=>spread("random")}><text fg="#63c7b2">R Random</text></box>
        <box flexShrink={0} backgroundColor="#293340" paddingX={1} onMouseDown={()=>setClicks(n=>n+1)}><text fg="#e9af70">Space UI counter {clicks}</text></box>
      </box>
      <text height={1} flexShrink={0} fg="#c2ced5">Heartbeat {tick}{paused?" paused":""} · P pause heartbeat · sent {counts[0]} · full {counts[1]} · Q exit</text>
      <box flexDirection="row" gap={2} flexGrow={1} flexShrink={1} minHeight={0} overflow="hidden">
        <box width="50%" border borderColor="#36535f" title={` Requests (${jobs.length}) `} paddingX={1} overflow="hidden">
          <scrollbox id="message-requests" width="100%" flexGrow={1} minHeight={0} scrollY stickyScroll stickyStart="bottom" contentOptions={{gap:0,paddingRight:1}} verticalScrollbarOptions={{width:1}}>
          {jobs.length===0?<text fg="#718b99">Send a job to start. Try a burst while it works.</text>:jobs.map(job=><box key={job.id} flexDirection="row" width="100%" height={1} flexShrink={0} gap={1}>
            <text width={15} flexShrink={0} fg={job.status==="done"?"#63c7b2":"#c2ced5"}>#{job.id} {job.status}</text>
            <ProgressBar progress={job.progress} style={barStyle}/>
            <text width={4} flexShrink={0} fg="#c2ced5">{`${job.progress}%`.padStart(4)}</text>
          </box>)}
          </scrollbox>
        </box>
        <box flexGrow={1} border borderColor="#36535f" title={` Native replies (${events.length}) `} paddingX={1} overflow="hidden">
          <scrollbox id="message-replies" width="100%" flexGrow={1} minHeight={0} scrollY stickyScroll stickyStart="bottom" contentOptions={{gap:0,paddingRight:1}} verticalScrollbarOptions={{width:1}}>
          {events.map((event,i)=><text key={i} height={1} flexShrink={0} fg="#a59de0">← #{event.id}  {event.type}  {event.progress}%</text>)}
          </scrollbox>
        </box>
      </box>
      <text height={1} flexShrink={0} fg="#718b99">V: bar style {barStyles[barStyle]} · C clear finished · R random</text>
    </box>
  </box>;
}
mountDemo(App);
if(__host.headless)Object.assign(globalThis,{
  async __selfTest(){
    const host=globalThis as any;
    const expect=(condition:boolean,message:string)=>{if(!condition)throw new Error(message)};
    const feed=(text:string)=>host.__input(new TextEncoder().encode(text).buffer);
    feed("s");feed(" ");
    expect(sent===1&&rejected===0,"initial request should be accepted");
    const first=1;
    const deadline=Date.now()+7000;
    while(!received.some(e=>e.type==="done"&&e.id===acceptedIds[acceptedIds.length-1])&&Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,10));
    expect(received.filter(e=>e.type==="done").length===sent,"all accepted requests must complete");
    expect(received.filter(e=>e.id===first).map(e=>e.progress).join(",")==="0,20,40,60,80,100","progress must preserve FIFO order");
    expect(uiTicks>1,"JS timers must run while worker is busy");
    await new Promise(resolve=>setTimeout(resolve,20));
    expect(host.__snapshot().includes("UI counter 1"),`React input must update during native work: ${host.__snapshot()}`);
    const spreadFirst=nextId;
    const started=Date.now();
    feed("f");
    while(!received.some(e=>e.id===spreadFirst+9&&e.type==="done")&&Date.now()-started<2500)await new Promise(resolve=>setTimeout(resolve,10));
    const events=received.filter(e=>e.id>=spreadFirst);
    const done=events.filter(e=>e.type==="done");
    expect(done.length===10,"spread must complete all ten requests");
    expect(events.slice(0,10).every(e=>e.progress===0),"all spread jobs must start before any completes");
    expect(new Set(done.map(e=>e.atMs)).size===1,"spread completions must share a native scheduler tick");
    expect(Date.now()-started<2500,"spread must overlap waits rather than take five seconds");
    const randomFirst=nextId;
    const randomStarted=Date.now();
    feed("r");
    while(!received.some(e=>e.id>=randomFirst&&e.type==="done")||received.filter(e=>e.id>=randomFirst&&e.type==="done").length<10){
      expect(Date.now()-randomStarted<5000,"random batch must finish within five seconds");
      await new Promise(resolve=>setTimeout(resolve,10));
    }
    const randomEvents=received.filter(e=>e.id>=randomFirst);
    for(let id=randomFirst;id<randomFirst+10;id++){
      const events=randomEvents.filter(e=>e.id===id);
      const elapsed=events[events.length-1].atMs-events[0].atMs;
      expect(elapsed>=1000&&elapsed<5000,"each random job must run between one and five seconds");
    }
    expect(new Set(randomEvents.filter(e=>e.type==="done").map(e=>e.atMs)).size>1,"random jobs should finish at different times");
    for(const style of ["segmented","thin","solid"]){
      feed("v");await new Promise(resolve=>setTimeout(resolve,20));
      expect(host.__snapshot().includes(`bar style ${style}`),"style key should cycle rendered bars");
    }
    const panels=["message-requests","message-replies"].map(id=>[...Renderable.renderablesByNumber.values()].find(node=>node.id===id) as any);
    expect(panels[0].scrollHeight>=sent,"request history must retain earlier batches");
    expect(panels[1].scrollHeight>=received.length,"reply history must retain every event");
    for(const panel of panels){
      panel.scrollTo(Infinity);
      await new Promise(resolve=>setTimeout(resolve,30));
      const before=panel.scrollTop;
      expect(before>0,"history must overflow its viewport");
      feed(`\x1b[<64;${panel.viewport.x+2};${panel.viewport.y+2}M`);
      await new Promise(resolve=>setTimeout(resolve,50));
      expect(panel.scrollTop<before,"wheel must scroll the hovered history panel");
      panel.scrollTo(0);
    }
    await new Promise(resolve=>setTimeout(resolve,30));
    expect(host.__snapshot().includes("← #1"),"oldest reply must remain accessible");
    feed("sc");
    await new Promise(resolve=>setTimeout(resolve,20));
    expect(host.__snapshot().includes("Requests (1)"),"clear finished must preserve new work");
    expect(!host.__snapshot().includes("← #1 "),"clear finished must remove replies for completed jobs");
    // Exit with work still queued to exercise worker stop/join on cleanup.
    const beforeBursts=sent;
    feed("bb");
    expect(sent===beforeBursts+24&&rejected===0,"two bursts must queue completely while a job is running");
  }
});
