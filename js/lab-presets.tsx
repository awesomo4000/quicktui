import {automaticName} from "./lab-preset-names";
import React,{useEffect,useState,useRef} from "../vendor/js/node_modules/react";
import {keys,interceptKeys} from "./platform/demo";
declare const __host:{postMessage(text:string):boolean};
export function PresetsPanel({capture,restore,close}:{capture:()=>any,restore:(value:any)=>void,close:()=>void}){
  const [slots,setSlots]=useState<{slot:number,description:string,description_auto?:boolean|null}[]>(Array.from({length:128},(_,i)=>({slot:i+1,description:""})));
  const scroll=useRef<any>(null);
  const [slot,setSlot]=useState(1),[description,setDescription]=useState("");
  const [editing,setEditing]=useState(false),[busy,setBusy]=useState(false),[notice,setNotice]=useState("");
  const request=(message:any)=>{
    if(busy)return;
    if(__host.postMessage(JSON.stringify(message))){setBusy(true);setNotice("Working…")}
    else setNotice("Worker busy. Try again.");
  };
  const choose=(value:number)=>{if(busy)return;setSlot(value);
    const node=scroll.current;if(node){const row=value-1;if(row<node.scrollTop)node.scrollTo(row);else if(row>=node.scrollTop+node.viewport.height)node.scrollTo(row-node.viewport.height+1)}
    setDescription(automaticName(slots[value-1])?"":slots[value-1].description);setEditing(false)};
  const save=()=>{
    const value=capture();
    value.description_auto=!description.trim();
    value.description=description.trim()||value.description;
    request({preset:"save",slot,value});setEditing(false);
  };
  const load=()=>request({preset:"load",slot});
  useEffect(()=>{
    let listed=false;
    const list=(start=1)=>{
      if(__host.postMessage(JSON.stringify({preset:"list",start}))){setBusy(true)}
      else {setBusy(false);setNotice("Worker busy. Close and reopen to retry.")}
    };
    const reply=(event:any)=>{
      if(event.error){setBusy(false);setNotice(event.error);return}
      if(event.value){setBusy(false);restore(event.value);return}
      if(event.slots){
        setSlots(previous=>{const next=[...previous];for(const entry of event.slots)next[entry.slot-1]=entry;return next});
        if(!listed&&event.slots[0]?.slot===1)setDescription(automaticName(event.slots[0])?"":event.slots[0].description);
        if(event.next){list(event.next);return}
        setBusy(false);
        if(!listed){setNotice("Choose a slot");listed=true}
        return;
      }
      if(event.saved){setNotice("Saved slot "+event.saved);list()}
    };
    keys.on("presets",reply);
    list();
    return()=>{keys.off("presets",reply)};
  },[]);
  useEffect(()=>{
    interceptKeys(key=>{
      const name=key.name.toLowerCase();
      if(key.ctrl&&name==="c")return false;
      if(name==="escape"){if(editing)setEditing(false);else close();return true}
      if(busy)return true;
      if(editing){
        if(name==="return"||name==="enter"){save();return true}
        if(name==="backspace"){setDescription(value=>Array.from(value).slice(0,-1).join(""));return true}
        const text=key.sequence??"";
        if(!key.ctrl&&!key.meta&&text&&Array.from(text).every((ch:string)=>{const cp=ch.codePointAt(0)??0;return cp>=32&&cp!==127}))
          setDescription(value=>{let next=Array.from(value+text).slice(0,120).join("");while(new TextEncoder().encode(next).length>240)next=Array.from(next).slice(0,-1).join("");return next});
        return true;
      }
      if(/^[1-9]$/.test(name))choose(Number(name));
      if(name==="up")choose(Math.max(1,slot-1));
      if(name==="down")choose(Math.min(128,slot+1));
      if(name==="home")choose(1);
      if(name==="end")choose(128);
      if(name==="pageup")choose(Math.max(1,slot-Math.max(1,scroll.current?.viewport.height??8)));
      if(name==="pagedown")choose(Math.min(128,slot+Math.max(1,scroll.current?.viewport.height??8)));
      if(name==="tab"){setEditing(true);return true}
      if(name==="a"){setDescription("");setEditing(false)}
      if(name==="s")save();
      if(name==="l"||name==="return"||name==="enter")load();
      return true;
    });
    return()=>interceptKeys(null);
  },[slot,description,editing,busy,slots]);
  const button=(label:string,action:()=>void)=><box height={1} flexShrink={0} paddingX={1} backgroundColor="#294650" onMouseDown={()=>{if(!busy)action()}}><text fg="#85ddca">{label}</text></box>;
  return <box position="absolute" left={1} top={1} width={72} maxWidth="95%" height={20} maxHeight="95%" border borderStyle="rounded" borderColor="#85ddca" backgroundColor="#14232c" padding={1} title=" Presets ">
    <text height={1} flexShrink={0} fg="#eee9dc">128 local slots · ↑↓ PgUp/PgDn Home/End · Tab name</text>
    <scrollbox ref={scroll} flexGrow={1} minHeight={0}>
      {slots.map(entry=><box key={entry.slot} height={1} flexShrink={0} backgroundColor={slot===entry.slot?"#294650":"#14232c"} onMouseDown={()=>choose(entry.slot)}>
        <text fg={slot===entry.slot?"#85ddca":"#96aeb8"}>{entry.slot}. {entry.description||"— empty —"}</text>
      </box>)}
    </scrollbox>
    <box height={2} flexShrink={0} onMouseDown={()=>setEditing(true)}>
      <text fg={editing?"#eee9dc":"#96aeb8"}>{description?"Custom:":"Auto:"} {description||(!editing?capture().description:"")}{editing?"▏":""}</text>
    </box>
    <box height={1} flexShrink={0} flexDirection="row" gap={2}>
      {button(slots[slot-1].description?"S · Overwrite":"S · Save",save)}
      {button("Enter · Load",load)}
      {button("A · Auto",()=>{setDescription("");setEditing(false)})}
      {button("Esc · Close",close)}
    </box>
    <text height={1} flexShrink={0} fg="#85ddca">{notice}{editing?" · Enter saves":""}</text>
    <text height={1} flexShrink={0} fg="#667f8b">.quicktui-presets/{slot}.json</text>
  </box>;
}
