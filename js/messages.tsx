import React, {useEffect, useState, useRef, useCallback} from "../vendor/js/node_modules/react";
import {Activity, type NativeBlink} from "./activity";
import {Renderable} from "../vendor/opentui/packages/core/src/Renderable";
import {mountDemo, keys} from "./platform/demo";

declare const __host:{postMessage(message:string):boolean,headless:boolean};
type Reply={id:number,type:"progress"|"done",progress:number,atMs:number};
type Job={id:number,progress:number,status:string};
type NativeEvent=Reply|NativeBlink;
const listeners=new Set<(event:NativeEvent)=>void>();
const nativeBlinks:NativeBlink[]=[];
const received:Reply[]=[];
const acceptedIds:number[]=[];
let nextId=1;
let sent=0,rejected=0,uiTicks=0;
// The host invokes this on the JS/UI thread, after draining the native queue.
Object.assign(globalThis,{__message(message:string){
  const event:NativeEvent=JSON.parse(message);
  if(__host.headless){if(event.type==="blink")nativeBlinks.push(event);else received.push(event);}
  for(const listener of listeners)listener(event);
}});
const barStyles=["solid","segmented","thin"] as const;
function ProgressBar({progress,style}:{progress:number,style:number}){
  const [width,setWidth]=useState(0);
  const filled=Math.round(width*progress/100);
  const color=progress===100?"#63c7b2":"#438b80";
  return <box flexGrow={1} flexBasis={0} minWidth={0} height={1} overflow="hidden"
    backgroundColor={style===0?"#243740":"#101820"}
    onSizeChange={function(this:{width:number}){setWidth(Math.max(0,Math.floor(this.width)))}}>
    {style===0?<box width={`${progress}%`} height={1} backgroundColor={color}/>:
      <text width="100%" height={1} fg={color}>{(style===1?"▰":"━").repeat(filled)}<span fg="#36535f">{(style===1?"·":"─").repeat(Math.max(0,width-filled))}</span></text>}
  </box>;
}
function useBorderScroll(){
  const node=useRef<any>(null);
  const attach=useCallback((scroll:any)=>{
    node.current=scroll;
    if(scroll){scroll.verticalScrollBar.visible=false;scroll.horizontalScrollBar.visible=false;}
  },[]);
  return {node,attach};
}
function BorderThumb({scroll,id}:{scroll:ReturnType<typeof useBorderScroll>,id:string}){
  const [position,setPosition]=useState({top:0,visible:false});
  const [hover,setHover]=useState(false);
  const [active,setActive]=useState(false);
  const drag=useRef<{y:number,start:number}|null>(null);
  useEffect(()=>{
    const timer=setInterval(()=>{
      const node=scroll.node.current;
      if(!node)return;
      const max=Math.max(0,node.scrollHeight-node.viewport.height);
      const top=max>0?Math.round(node.scrollTop/max*Math.max(0,node.height-1)):0;
      const visible=max>0;
      setPosition(old=>old.top===top&&old.visible===visible?old:{top,visible});
    },16);
    return()=>clearInterval(timer);
  },[scroll.node]);
  return <text id={id} position="absolute" right={-1} top={position.top} width={1} height={1} zIndex={10} visible={position.visible}
    fg={active?"#8cdecc":hover?"#63c7b2":"#526b78"} bg="#101820"
    onMouseOver={()=>setHover(true)} onMouseOut={()=>setHover(false)}
    onMouseDown={(event:any)=>{if(event.button!==0)return;drag.current={y:event.y,start:scroll.node.current.scrollTop};setActive(true);event.stopPropagation()}}
    onMouseDrag={(event:any)=>{
      const node=scroll.node.current,start=drag.current;
      if(!node||!start)return;
      const max=Math.max(0,node.scrollHeight-node.viewport.height);
      node.scrollTo(Math.max(0,Math.min(max,start.start+(event.y-start.y)*max/Math.max(1,node.height-1))));
      event.stopPropagation();
    }}
    onMouseUp={(event:any)=>{if(event.button!==0)return;drag.current=null;setActive(false);event.stopPropagation()}}>┃</text>;
}
function App(){
  const requestEdges=useBorderScroll();
  const replyEdges=useBorderScroll();
  const splitRow=useRef<any>(null);
  const dragging=useRef(false);
  const grabOffset=useRef(0);
  const [rowWidth,setRowWidth]=useState(0);
  const [split,setSplit]=useState(0.65);
  const [dividerHover,setDividerHover]=useState(false);
  const [dividerActive,setDividerActive]=useState(false);
  function resizeSplit(x:number){
    const row=splitRow.current;
    if(!row)return;
    const available=Math.max(1,row.width-1);
    const minLeft=Math.min(30,available*0.4);
    const minRight=Math.min(20,available*0.3);
    setSplit(Math.max(minLeft,Math.min(available-minRight,x-row.x-grabOffset.current))/available);
  }
  const rightColumn=useRef<any>(null);
  const verticalDrag=useRef(false);
  const verticalGrab=useRef(0);
  const [rightHeight,setRightHeight]=useState(0);
  const [verticalSplit,setVerticalSplit]=useState(0.5);
  const [horizontalHover,setHorizontalHover]=useState(false);
  const [horizontalActive,setHorizontalActive]=useState(false);
  function resizeVertical(y:number){
    const column=rightColumn.current;
    if(!column)return;
    const available=Math.max(1,column.height-1);
    const minTop=Math.min(3,available*0.4),minBottom=Math.min(5,available*0.4);
    setVerticalSplit(Math.max(minTop,Math.min(available-minBottom,y-column.y-verticalGrab.current))/available);
  }
  const topHeight=rightHeight?Math.max(Math.min(3,(rightHeight-1)*0.4),Math.min(rightHeight-1-Math.min(5,(rightHeight-1)*0.4),Math.round((rightHeight-1)*verticalSplit))):"50%";
  const [pulse,setPulse]=useState<NativeBlink|null>(null);
  const [barStyle,setBarStyle]=useState(0);
  const [jobs,setJobs]=useState<Job[]>([]);
  const [tick,setTick]=useState(0);
  const [paused,setPaused]=useState(false);
  const [clicks,setClicks]=useState(0);
  const [counts,setCounts]=useState([0,0]);
  const [events,setEvents]=useState<NativeEvent[]>([]);
  const finished=useRef(new Set<number>());
  function clearFinished(){
    const ids=new Set(finished.current);
    finished.current.clear();
    setJobs(rows=>rows.filter(row=>!ids.has(row.id)));
    setEvents(rows=>rows.filter(event=>event.type==="blink"||!ids.has(event.id)));
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
    const listener=(event:NativeEvent)=>{
      if(event.type==="blink"){setPulse(event);setEvents(rows=>[...rows,event]);return;}
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
      <box id="message-split" ref={splitRow} onSizeChange={function(this:{width:number}){setRowWidth(this.width)}} flexDirection="row" flexGrow={1} flexShrink={1} minHeight={0} overflow="hidden">
        <box id="message-request-panel" width={rowWidth?Math.max(30,Math.min(rowWidth-21,Math.round((rowWidth-1)*split))):"65%"} flexShrink={0} border borderColor="#36535f" title={` Requests (${jobs.length}) `} paddingX={1}>
          <scrollbox id="message-requests" ref={requestEdges.attach} width="100%" flexGrow={1} minHeight={0} scrollY stickyScroll stickyStart="bottom" contentOptions={{gap:0}}>
          {jobs.length===0?<text fg="#718b99">Send a job to start. Try a burst while it works.</text>:jobs.map(job=><box key={job.id} flexDirection="row" width="100%" height={1} flexShrink={0} gap={1}>
            <text width={15} flexShrink={0} fg={job.status==="done"?"#63c7b2":"#c2ced5"}>#{job.id} {job.status}</text>
            <ProgressBar progress={job.progress} style={barStyle}/>
            <text id={`message-percent-${job.id}`} width={4} flexShrink={0} fg="#c2ced5">{`${job.progress}%`.padStart(4)}</text>
          </box>)}
          </scrollbox>
          <BorderThumb id="request-scroll-thumb" scroll={requestEdges}/>
        </box>
        <box id="message-divider" width={1} flexShrink={0} height="100%" justifyContent="center" alignItems="center"
          backgroundColor="#101820"
          onMouseOver={()=>setDividerHover(true)} onMouseOut={()=>setDividerHover(false)}
          onMouseDown={(event:any)=>{if(event.button!==0)return;grabOffset.current=event.x-event.currentTarget.x;dragging.current=true;setDividerActive(true);event.stopPropagation()}}
          onMouseDrag={(event:any)=>{if(dragging.current){resizeSplit(event.x);event.stopPropagation()}}}
          onMouseUp={(event:any)=>{if(event.button!==0)return;dragging.current=false;setDividerActive(false);event.stopPropagation()}}>
          <box width={1} height="100%" backgroundColor={dividerActive?"#36535f":dividerHover?"#243740":"#101820"}/>
        </box>
        <box id="message-right-column" ref={rightColumn} flexGrow={1} flexBasis={0} minWidth={20} minHeight={0}
          onSizeChange={function(this:{height:number}){setRightHeight(this.height)}}>
        <box id="message-reply-panel" height={topHeight} flexShrink={0} border borderColor="#36535f" title={` Native replies (${events.length}) `} paddingX={1}>
          <scrollbox id="message-replies" ref={replyEdges.attach} width="100%" flexGrow={1} minHeight={0} scrollY stickyScroll stickyStart="bottom" contentOptions={{gap:0}}>
          {events.map((event,i)=><text key={i} height={1} flexShrink={0} fg="#a59de0">{event.type==="blink"?`← blink #${event.sequence}: ${event.cells.length} cells`:`← #${event.id}  ${event.type}  ${event.progress}%`}</text>)}
          </scrollbox>
          <BorderThumb id="reply-scroll-thumb" scroll={replyEdges}/>
        </box>
        <box id="message-horizontal-divider" width="100%" height={1} flexShrink={0}
          backgroundColor={horizontalActive?"#36535f":horizontalHover?"#243740":"#101820"}
          onMouseOver={()=>setHorizontalHover(true)} onMouseOut={()=>setHorizontalHover(false)}
          onMouseDown={(event:any)=>{if(event.button!==0)return;verticalGrab.current=event.y-event.currentTarget.y;verticalDrag.current=true;setHorizontalActive(true);event.stopPropagation()}}
          onMouseDrag={(event:any)=>{if(verticalDrag.current){resizeVertical(event.y);event.stopPropagation()}}}
          onMouseUp={(event:any)=>{if(event.button!==0)return;verticalDrag.current=false;setHorizontalActive(false);event.stopPropagation()}}/>
        <Activity pulse={pulse}/>
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
    const idleDeadline=Date.now()+5500;
    while(nativeBlinks.length===0&&Date.now()<idleDeadline)await new Promise(resolve=>setTimeout(resolve,10));
    expect(nativeBlinks.length===1&&sent===0,"native must emit a blink while idle, without a JS request");
    const blinkReceivedAt=Date.now();
    const firstBlink=nativeBlinks[0];
    expect(firstBlink.sequence===1,"first native blink must have sequence one");
    await new Promise(resolve=>setTimeout(resolve,40));
    const cells=()=>[...Renderable.renderablesByNumber.values()].filter(node=>node.id.startsWith("activity-cell-")) as any[];
    const lit=cells().filter(node=>node.backgroundColor?.toInts().slice(0,3).join(",")==="245,244,223");
    expect(firstBlink.cells.length>=1&&firstBlink.cells.length<=Math.min(10,firstBlink.columns*firstBlink.rows),"native blink count must fit the grid");
    expect(new Set(firstBlink.cells).size===firstBlink.cells.length,"native blink selections must be unique");
    expect(lit.length===firstBlink.cells.length,"native event must light exactly the selected squares");
    for(const cell of firstBlink.cells){
      expect(lit.some(node=>node.id===`activity-cell-${cell%firstBlink.columns}-${Math.floor(cell/firstBlink.columns)}`),"UI must honor native-selected coordinates without remapping");
    }
    const selected=lit;
    const waitForAge=async(age:number)=>{while(Date.now()-blinkReceivedAt<age)await new Promise(resolve=>setTimeout(resolve,10))};
    const allColor=(color:string)=>selected.every(node=>node.backgroundColor.toInts().slice(0,3).join(",")===color);
    await waitForAge(300);expect(allColor("16,24,32"),"first blink must go dark");
    await waitForAge(500);expect(allColor("245,244,223"),"second blink must light the same square");
    await waitForAge(700);expect(allColor("16,24,32"),"second blink must go dark");
    await waitForAge(900);expect(!allColor("245,244,223")&&!allColor("16,24,32"),"square must resume its underlying pulse");
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
    const find=(id:string)=>[...Renderable.renderablesByNumber.values()].find(node=>node.id===id) as any;
    const divider=find("message-divider"),left=find("message-request-panel"),right=find("message-reply-panel");
    const widthBefore=left.width;
    const startX=divider.x;
    // Every cell in the handle must preserve its grab offset without a jump.
    for(let offset=0;offset<1;offset++){
      const x=divider.x+offset;
      feed(`\x1b[<0;${x+1};${divider.y+2}M`);
      feed(`\x1b[<32;${x+1};${divider.y+2}M`);
      host.__frame();
      expect(divider.x===startX,"stationary drag must not jump at any grab point");
      feed(`\x1b[<32;${x+2};${divider.y+2}M`);
      host.__frame();
      expect(divider.x===startX+1,"divider must track a one-column drag exactly");
      feed(`\x1b[<32;${x+1};${divider.y+2}M`);
      host.__frame();
      expect(divider.x===startX,"reverse drag must return exactly without drift");
      feed(`\x1b[<0;${x+1};${divider.y+2}m`);
    }
    expect(left.width>right.width,"requests should start wider than replies");
    feed(`\x1b[<0;${divider.x+1};${divider.y+2}M`);
    feed(`\x1b[<32;${divider.x-7};${divider.y+2}M`);
    feed(`\x1b[<0;${divider.x-7};${divider.y+2}m`);
    await new Promise(resolve=>setTimeout(resolve,30));
    expect(left.width<widthBefore&&left.width>=30&&right.width>=20,"divider drag must resize panes and preserve minimum widths");
    const requestScroll=find("message-requests");
    requestScroll.scrollTo(0);
    await new Promise(resolve=>setTimeout(resolve,50));
    const percent=find("message-percent-1");
    expect(percent.x+percent.width<=requestScroll.viewport.x+requestScroll.viewport.width,`percentage outside resized viewport: ${percent.x}+${percent.width}, viewport ${requestScroll.viewport.x}+${requestScroll.viewport.width}`);
    expect(host.__snapshot().split("\n").some((line:string)=>line.includes("100%")),`completed percentages should remain visible after narrowing: ${host.__snapshot()}`);
    for(let style=0;style<3;style++){
      const divider=find("message-divider"),row=find("message-split");
      feed(`\x1b[<0;${divider.x+1};${divider.y+2}M`);
      for(const width of [row.width-22,30,row.width-22,30]){
        feed(`\x1b[<32;${row.x+width+1};${divider.y+2}M`);
        await new Promise(resolve=>setTimeout(resolve,30));
        const scroll=find("message-requests");scroll.scrollTo(0);
        await new Promise(resolve=>setTimeout(resolve,30));
        const label=find("message-percent-1");
        expect(label.x+label.width<=scroll.viewport.x+scroll.viewport.width,`style ${style} percentage clipped after wide/narrow cycle`);
      }
      feed(`\x1b[<0;${divider.x+1};${divider.y+2}m`);
      feed("v");await new Promise(resolve=>setTimeout(resolve,30));
    }
    const horizontal=find("message-horizontal-divider"),activity=find("message-activity");
    expect(divider.width===1&&horizontal.height===1,"dividers must be one cell thick");
    const horizontalY=horizontal.y;
    feed(`\x1b[<0;${horizontal.x+2};${horizontal.y+1}M`);
    feed(`\x1b[<32;${horizontal.x+2};${horizontalY+1}M`);
    host.__frame();
    expect(horizontal.y===horizontalY,"horizontal divider must not jump on grab");
    feed(`\x1b[<32;${horizontal.x+2};${horizontalY}M`);
    host.__frame();
    expect(horizontal.y===horizontalY-1,"horizontal divider must track one row");
    feed(`\x1b[<0;${horizontal.x+2};${horizontalY}m`);
    expect(activity.height>0,"activity pane must retain visible space");
    const panels=["message-requests","message-replies"].map(id=>[...Renderable.renderablesByNumber.values()].find(node=>node.id===id) as any);
    expect(panels[0].scrollHeight>=sent,"request history must retain earlier batches");
    expect(panels[1].scrollHeight>=received.length,"reply history must retain every event");
    for(const panel of panels){
      panel.scrollTo(Infinity);
      await new Promise(resolve=>setTimeout(resolve,30));
      expect(!panel.verticalScrollBar.visible&&panel.viewport.width===panel.width,"scrollbar must not reserve a column");
      const before=panel.scrollTop;
      expect(before>0,"history must overflow its viewport");
      feed(`\x1b[<64;${panel.viewport.x+2};${panel.viewport.y+2}M`);
      await new Promise(resolve=>setTimeout(resolve,50));
      expect(panel.scrollTop<before,"wheel must scroll the hovered history panel");
      panel.scrollTo(0);
    }
    await new Promise(resolve=>setTimeout(resolve,30));
    for(const [panelId,thumbId] of [["message-request-panel","request-scroll-thumb"],["message-reply-panel","reply-scroll-thumb"]]){
      const panel=find(panelId),thumb=find(thumbId);
      expect(thumb.x===panel.x+panel.width-1,`thumb must overlay border: ${thumb.x} vs ${panel.x+panel.width-1}`);
      const scroll=panelId==="message-request-panel"?panels[0]:panels[1];
      feed(`\x1b[<0;${thumb.x+1};${thumb.y+1}M`);
      feed(`\x1b[<32;${thumb.x+1};${thumb.y+2}M`);
      feed(`\x1b[<0;${thumb.x+1};${thumb.y+2}m`);
      expect(scroll.scrollTop>0,"border thumb must drag-scroll history");
      scroll.scrollTo(0);
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
