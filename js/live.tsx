import React,{useEffect,useRef,useState} from "../vendor/js/node_modules/react";
import {mountDemo,keys} from "./platform/demo";
declare const __host:{headless:boolean,postMessage(text:string):boolean,takeBuffer(id:number):ArrayBuffer|null};
type Extension={id:string,owner:string,title:string,render:()=>React.ReactNode,revision:number};
let extensions:Extension[]=[];
let revision=0;
let epoch=0;
const changed=()=>keys.emit("live-change");
function evaluate(source:string,file:string){
  const staged=new Map<string,Omit<Extension,"revision">>();
  const api=Object.freeze({register(id:string,definition:{title:string,render:()=>React.ReactNode}){
    if(typeof id!=="string"||!id||id.length>80||typeof definition?.render!=="function"||typeof definition?.title!=="string")throw new Error("register expects an ID, title, and render function");
    if(extensions.some(item=>item.id===id&&item.owner!==file))throw new Error("ID belongs to another script: "+id);
    if(staged.size>=16&&!staged.has(id))throw new Error("Limit: 16 registrations per script");
    staged.set(id,{id,owner:file,title:definition.title,render:definition.render});
  }});
  try {
    const execute=new Function("React","h","api",source+"\n//# sourceURL="+file+".js");
    const result=execute(React,React.createElement,api);
    if(result&&typeof result.then==="function")throw new Error("Top-level loading must be synchronous; use effects for async work");
    revision++;
    const remaining=new Map(staged);
    extensions=extensions.flatMap(item=>{
      if(item.owner!==file)return [item];
      const replacement=remaining.get(item.id);remaining.delete(item.id);
      return replacement?[{...replacement,revision}]:[];
    });
    extensions.push(...Array.from(remaining.values(),item=>({...item,revision})));
    keys.emit("live-status",file+".js loaded · "+staged.size+" component(s) · revision "+revision);
    changed();return true;
  }catch(error){
    keys.emit("live-status","Load failed: "+String(error));return false;
  }
}
Object.assign(globalThis,{__message(message:string){
  const event=JSON.parse(message);if(event.type!=="source"||event.epoch!==epoch)return;
  if(event.error){keys.emit("live-status",event.file+".js: "+event.error);return}
  const bytes=__host.takeBuffer(event.id);if(!bytes)return;
  evaluate(new TextDecoder().decode(bytes),event.file);
}});
class ExtensionBoundary extends React.Component<{children:React.ReactNode},{error:string|null}> {
  state={error:null as string|null};
  static getDerivedStateFromError(error:unknown){return {error:String(error)}}
  render(){return this.state.error?<text fg="#ee9b86">Component failed: {this.state.error}</text>:this.props.children}
}
function App(){
  const [count,setCount]=useState(0),[items,setItems]=useState(extensions),[status,setStatus]=useState("Load a script to extend this page.");
  const [selected,setSelected]=useState("counter"),[watch,setWatch]=useState(false);
  const selection=useRef({file:"counter",watch:false});
  const request=(file=selection.current.file,watching=selection.current.watch)=>{
    selection.current={file,watch:watching};
    setSelected(file);setWatch(watching);
    if(!__host.postMessage(JSON.stringify({load:file,watch:watching,epoch})))setStatus("Loader rejected request");
  };
  const clear=()=>{
    epoch++;
    __host.postMessage(JSON.stringify({load:"clear",epoch}));
    selection.current={file:"counter",watch:false};
    setSelected("counter");setWatch(false);
    extensions=[];changed();
    setStatus("Components cleared. Press 1 to load the counter, then 2 to add the clock.");
  };
  useEffect(()=>{
    const update=()=>setItems([...extensions]);
    keys.on("live-change",update);keys.on("live-status",setStatus);
    return()=>{keys.off("live-change",update);keys.off("live-status",setStatus)};
  },[]);
  useEffect(()=>{
    const key=(name:string)=>{
      if(name==="space")setCount(value=>value+1);
      if(name==="1")request("counter");
      if(name==="2")request("clock");
      if(name==="r")request();
      if(name==="c")clear();
      if(name==="w")request(selection.current.file,!selection.current.watch)
    };
    keys.on("key",key);return()=>{keys.off("key",key)};
  },[]);
  const button=(label:string,fn:()=>void)=><box paddingX={1} backgroundColor="#294650" onMouseDown={fn}><text fg="#85ddca">{label}</text></box>;
  return <box width="100%" height="100%" padding={1} backgroundColor="#101820">
    <box width="100%" height="100%" border borderStyle="rounded" borderColor="#85ddca" title=" 06 / Live JavaScript " padding={1} gap={1}>
      <text height={1} flexShrink={0} fg="#eee9dc">One running page. Load more code.</text>
      <box height={1} flexShrink={0} flexDirection="row" gap={2}>
        <text fg="#edce86">Host count: {count}</text>
        {button("Space / click +1",()=>setCount(value=>value+1))}
      </box>
      <box height={1} flexShrink={0} flexDirection="row" gap={1}>
        {button("1 Load counter.js",()=>request("counter"))}
        {button("2 Add clock.js",()=>request("clock"))}
        {button("R Reload",()=>request())}
        {button("C Clear",clear)}
      </box>
      <text height={1} flexShrink={0} fg="#96aeb8">Selected: {selected}.js · W watch: {watch?"ON":"off"} · Q exit</text>
      <scrollbox flexGrow={1} minHeight={0}>
        <box gap={1} width="100%">
          {items.length===0?<text fg="#667f8b">No components loaded. Press 1 for the counter, then 2 to add the clock.</text>:items.map(item=>
            <box key={item.id} border borderStyle="rounded" borderColor="#3c626d" paddingX={1} width="100%" title={" "+item.id+" / "+item.owner+".js "}>
              <box flexDirection="column" paddingY={1} gap={1} width="100%">
                <text fg="#85ddca">{item.title}</text>
                <ExtensionBoundary key={item.revision}><item.render/></ExtensionBoundary>
              </box>
            </box>)}
        </box>
      </scrollbox>
      <text height={2} flexShrink={0} fg={status.includes("failed")?"#ee9b86":"#85ddca"}>{status}</text>
      <text height={2} flexShrink={0} fg="#667f8b">Edit examples/live/*.js, then reload. Shared React and QuickJS stay alive. Replaced extensions remount; the host and other extensions retain their state.</text>
    </box>
  </box>;
}
mountDemo(App,{onCaughtError(error){keys.emit("live-status","Component failed: "+String(error))}});
if(__host.headless)Object.assign(globalThis,{async __selfTest(){
  const host=globalThis as any;
  host.__resize(110,40);
  const wait=()=>new Promise(resolve=>setTimeout(resolve,25));
  const until=async(text:string)=>{const end=Date.now()+3000;while(!host.__snapshot().includes(text)&&Date.now()<end)await wait();if(!host.__snapshot().includes(text))throw new Error("Missing live state: "+text+"\n"+host.__snapshot())};
  host.__input(new TextEncoder().encode(" ").buffer);
  host.__input(new TextEncoder().encode("1").buffer);await until("A counter loaded from JavaScript");
  host.__input(new TextEncoder().encode("2").buffer);await until("A clock added by a second script");
  await until("Host count: 1");
  evaluate('api.register("counter",{title:"Replacement counter",render:()=>h("text",{},"new code")});',"counter");
  await until("Replacement counter");await until("A clock added by a second script");await until("Host count: 1");
  evaluate('api.register("counter",{title:"Effect test",render:()=>{React.useEffect(()=>{globalThis.__liveEffectMounted=true;return()=>{globalThis.__liveEffectCleaned=true}},[]);return h("text",{},"effect mounted")}});',"counter");
  await until("effect mounted");await wait();
  if(!host.__liveEffectMounted)throw new Error("Extension effect did not mount");
  evaluate('api.register("counter",{title:"Replacement counter",render:()=>h("text",{},"new code")});',"counter");
  await until("Replacement counter");await wait();
  if(!host.__liveEffectCleaned)throw new Error("Replaced extension effect was not cleaned up");
  if(extensions.map(item=>item.id).join(",")!=="counter,clock")throw new Error("Reload moved components");
  const before=revision;
  if(evaluate('api.register("counter",{title:"bad",render:()=>null}); throw new Error("expected");',"counter"))throw new Error("Failed load committed");
  if(revision!==before||extensions.find(item=>item.id==="counter")?.title!=="Replacement counter")throw new Error("Failed loads must preserve registrations");
  if(evaluate("const = ;","counter"))throw new Error("Syntax error accepted");
  evaluate('api.register("counter",{title:"Throwing component",render:()=>{throw new Error("render test")}});',"counter");
  await until("Component failed:");await until("Host count: 1");await until("A clock added by a second script");
  evaluate('api.register("counter",{title:"Recovered",render:()=>h("text",{},"working again")});',"counter");
  await until("working again");
  host.__input(new TextEncoder().encode("wc").buffer);
  await until("Components cleared.");await wait();
  if(extensions.length||host.__snapshot().includes("working again"))throw new Error("Clear left components mounted");
  await until("Host count: 1");await until("watch: off");
  host.__input(new TextEncoder().encode("1").buffer);await until("A counter loaded from JavaScript");
  host.__input(new TextEncoder().encode("2").buffer);await until("A clock added by a second script");
}});
