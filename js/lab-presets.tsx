import React,{useEffect,useState} from "../vendor/js/node_modules/react";
import {keys,interceptKeys} from "./platform/demo";
declare const __host:{postMessage(text:string):boolean};
export function PresetsPanel({capture,restore,close}:{capture:()=>any,restore:(value:any)=>void,close:()=>void}){
  const [slots,setSlots]=useState<{slot:number,description:string}[]>(Array.from({length:9},(_,i)=>({slot:i+1,description:""})));
  const [slot,setSlot]=useState(1),[description,setDescription]=useState("");
  const [editing,setEditing]=useState(false),[busy,setBusy]=useState(false),[notice,setNotice]=useState("");
  const request=(message:any)=>{
    if(busy)return;
    if(__host.postMessage(JSON.stringify(message))){setBusy(true);setNotice("Working…")}
    else setNotice("Worker busy. Try again.");
  };
  const choose=(value:number)=>{setSlot(value);setDescription(slots[value-1].description);setEditing(false)};
  const save=()=>{
    const value=capture();
    value.description=description.trim()||value.description;
    request({preset:"save",slot,value});setEditing(false);
  };
  const load=()=>request({preset:"load",slot});
  useEffect(()=>{
    let listed=false;
    const reply=(event:any)=>{
      setBusy(false);
      if(event.error){setNotice(event.error);return}
      if(event.value){restore(event.value);return}
      if(event.slots){setSlots(event.slots);if(!listed){setDescription(event.slots[0].description);setNotice("Choose a slot");listed=true}return}
      if(event.saved){
        setNotice("Saved slot "+event.saved);
        __host.postMessage(JSON.stringify({preset:"list"}));
      }
    };
    keys.on("presets",reply);
    __host.postMessage(JSON.stringify({preset:"list"}));
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
          setDescription(value=>Array.from(value+text).slice(0,60).join(""));
        return true;
      }
      if(/^[1-9]$/.test(name))choose(Number(name));
      if(name==="up")choose(Math.max(1,slot-1));
      if(name==="down")choose(Math.min(9,slot+1));
      if(name==="tab"){setEditing(true);return true}
      if(name==="s")save();
      if(name==="l"||name==="return"||name==="enter")load();
      return true;
    });
    return()=>interceptKeys(null);
  },[slot,description,editing,busy,slots]);
  const button=(label:string,action:()=>void)=><box height={1} flexShrink={0} paddingX={1} backgroundColor="#294650" onMouseDown={()=>{if(!busy)action()}}><text fg="#85ddca">{label}</text></box>;
  return <box position="absolute" left={1} top={1} width={72} maxWidth="95%" height={20} maxHeight="95%" border borderStyle="rounded" borderColor="#85ddca" backgroundColor="#14232c" padding={1} title=" Presets ">
    <text height={1} flexShrink={0} fg="#eee9dc">Nine local slots · 1–9 select · Tab edit description</text>
    <scrollbox flexGrow={1} minHeight={0}>
      {slots.map(entry=><box key={entry.slot} height={1} flexShrink={0} backgroundColor={slot===entry.slot?"#294650":"#14232c"} onMouseDown={()=>choose(entry.slot)}>
        <text fg={slot===entry.slot?"#85ddca":"#96aeb8"}>{entry.slot}. {entry.description||"— empty —"}</text>
      </box>)}
    </scrollbox>
    <box height={2} flexShrink={0} onMouseDown={()=>setEditing(true)}>
      <text fg={editing?"#eee9dc":"#96aeb8"}>Description: {description||"(automatic description)"}{editing?"▏":""}</text>
    </box>
    <box height={1} flexShrink={0} flexDirection="row" gap={2}>
      {button(slots[slot-1].description?"S · Overwrite":"S · Save",save)}
      {button("Enter · Load",load)}
      {button("Esc · Close",close)}
    </box>
    <text height={1} flexShrink={0} fg="#85ddca">{notice}{editing?" · Enter saves":""}</text>
    <text height={1} flexShrink={0} fg="#667f8b">.quicktui-presets/{slot}.json</text>
  </box>;
}
