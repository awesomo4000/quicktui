import {Renderable} from "../vendor/opentui/packages/core/src/Renderable";
import React,{useEffect,useRef,useState} from "../vendor/js/node_modules/react";
declare const __host:{headless:boolean,postMessage(text:string):boolean,takeBuffer(id:number):ArrayBuffer|null,quit():void};
let pending:{resolve:(v:any)=>void,reject:(e:Error)=>void}|null=null;
export function receiveEditorMessage(text:string){
  const reply=JSON.parse(text),waiter=pending;pending=null;
  if(reply.error)waiter?.reject(new Error(reply.error));else waiter?.resolve(reply);
}
function request(value:any):Promise<any>{
  return new Promise((resolve,reject)=>{
    if(pending){reject(new Error("Worker busy"));return}
    pending={resolve,reject};
    if(!__host.postMessage(JSON.stringify(value))){pending=null;reject(new Error("Worker busy"))}
  });
}
export function Editor({keys}:{keys:any}){
  const editor=useRef<any>(null),pathInput=useRef<any>(null),recentScroll=useRef<any>(null);
  const [path,setPath]=useState(""),[text,setText]=useState(""),[saved,setSaved]=useState("");
  const [busy,setBusy]=useState(false),[status,setStatus]=useState("New document");
  const [confirm,setConfirm]=useState<{label:string,action:()=>void}|null>(null);
  const [menu,setMenu]=useState(false),[item,setItem]=useState(0),[submenu,setSubmenu]=useState(false),[recentIndex,setRecentIndex]=useState(0);
  const [recents,setRecents]=useState<string[]>([]);
  const [dialog,setDialog]=useState<"open"|"save"|null>(null),[filename,setFilename]=useState("");
  const dirty=text!==saved;
  const remember=(name:string)=>setRecents(previous=>[name,...previous.filter(value=>value!==name)].slice(0,16));
  const closeMenu=()=>{setMenu(false);setSubmenu(false)};
  const openDialog=(kind:"open"|"save")=>{closeMenu();setFilename(path);setDialog(kind)};
  const doLoad=async(name:string)=>{
    if(busy)return;setBusy(true);setConfirm(null);
    try{
      const reply=await request({op:"load",path:name});
      const bytes=__host.takeBuffer(reply.id);if(!bytes)throw new Error("Missing file contents");
      const value=new TextDecoder().decode(bytes);
      editor.current.setText(value);setText(value);setSaved(value);setPath(name);remember(name);
      setStatus("Loaded");
    }catch(error){setStatus("Load failed: "+(error as Error).message)}
    finally{setBusy(false)}
  };
  const load=(name:string)=>{closeMenu();setDialog(null);if(dirty)setConfirm({label:"Discard unsaved changes and load?",action:()=>void doLoad(name)});else void doLoad(name)};
  const save=async(name=path,overwrite=false)=>{
    if(busy)return;
    if(!name){openDialog("save");return}
    const value=editor.current.plainText;
    if(new TextEncoder().encode(value).length>65536){setStatus("Save limit: 64 KiB");return}
    closeMenu();setDialog(null);setBusy(true);setConfirm(null);
    try{
      await request({op:"begin"});
      const chars=Array.from(value);
      for(let i=0;i<chars.length;i+=256)await request({op:"append",text:chars.slice(i,i+256).join("")});
      await request({op:"save",path:name,overwrite});
      setPath(name);remember(name);setSaved(value);setStatus("Saved");
    }catch(error){
      if((error as Error).message==="FileExists")setConfirm({label:"Replace the existing file?",action:()=>void save(name,true)});
      else setStatus("Save failed: "+(error as Error).message);
    }finally{setBusy(false)}
  };
  const quit=()=>{closeMenu();if(dirty)setConfirm({label:"Quit and discard unsaved changes?",action:()=>__host.quit()});else __host.quit()};
  const activate=(index:number)=>{
    if(busy)return;
    if(index===0)openDialog("open");
    if(index===1)void save();
    if(index===2)openDialog("save");
    if(index===3){setSubmenu(true);setRecentIndex(0)}
    if(index===4)quit();
  };
  const submit=()=>{if(!filename.trim()){setStatus("Enter a filename");return}if(dialog==="open")load(filename);else void save(filename)};
  useEffect(()=>{
    void request({op:"info"}).then(reply=>{
      setPath(reply.path);
      if(reply.path&&!__host.headless)void doLoad(reply.path);
    }).catch(error=>setStatus(error.message));
  },[]);
  useEffect(()=>{
    if(menu||confirm||busy){editor.current?.blur();pathInput.current?.blur()}
    else if(dialog){editor.current?.blur();pathInput.current?.focus()}
    else editor.current?.focus();
  },[menu,dialog,confirm,busy]);
  useEffect(()=>{
    const node=recentScroll.current;
    if(node){if(recentIndex<node.scrollTop)node.scrollTo(recentIndex);else if(recentIndex>=node.scrollTop+node.viewport.height)node.scrollTo(recentIndex-node.viewport.height+1)}
  },[recentIndex,submenu]);
  useEffect(()=>{
    const key=(event:any)=>{
      const name=event.name;
      const stop=()=>{event.preventDefault();event.stopPropagation()};
      if(busy){stop();return}
      if(confirm){
        stop();
        if(name==="escape")setConfirm(null);
        if(name==="return")confirm.action();
        return;
      }
      if(dialog){
        if(name==="escape"){stop();setDialog(null)}
        if(name==="return"){stop();submit()}
        return;
      }
      if(event.meta&&name==="f"){stop();setMenu(!menu);setSubmenu(false);setItem(0);return}
      if(menu){
        stop();
        if(name==="escape"){if(submenu)setSubmenu(false);else closeMenu()}
        if(submenu){
          if(name==="left")setSubmenu(false);
          if(recents.length){
            if(name==="up")setRecentIndex(value=>(value+recents.length-1)%recents.length);
            if(name==="down")setRecentIndex(value=>(value+1)%recents.length);
            if(name==="return")load(recents[recentIndex]);
          }
        }else{
          if(name==="up")setItem(value=>(value+4)%5);
          if(name==="down")setItem(value=>(value+1)%5);
          if(name==="right"&&item===3){setSubmenu(true);setRecentIndex(0)}
          if(name==="return")activate(item);
        }
        return;
      }
      if(name==="down"&&!event.ctrl&&!event.meta&&!event.shift&&editor.current?.focused){
        stop();
        const node=editor.current,before=node.cursorOffset;
        node.moveCursorDown();
        if(node.cursorOffset===before&&node.logicalCursor.row===node.lineCount-1)node.gotoLineTextEnd();
        return;
      }
      if(event.ctrl&&name==="s"){stop();void save()}
      if(event.ctrl&&name==="o"){stop();openDialog("open")}
      if(event.ctrl&&(name==="q"||name==="c")){stop();quit()}
    };
    keys.on("keypress",key);return()=>keys.off("keypress",key);
  },[path,text,saved,busy,confirm,dialog,filename,menu,item,submenu,recents,recentIndex]);
  const labels=["Open…        Ctrl+O","Save         Ctrl+S","Save as…","Recent files      ›","Quit         Ctrl+Q"];
  return <box width="100%" height="100%" padding={1} backgroundColor="#101820" gap={1}>
    <box height={1} flexDirection="row" gap={2}>
      <box id="editor-file-menu" paddingX={1} backgroundColor={menu?"#294650":"#20353f"} onMouseDown={()=>{if(!busy&&!confirm&&!dialog){setMenu(!menu);setSubmenu(false);setItem(0)}}}><text fg="#85ddca">File</text></box>
      <text fg="#96aeb8">{path||"Untitled"}{dirty?" *":""} · 07 / Editor</text>
    </box>
    <box border borderStyle="rounded" borderColor="#36545e" flexGrow={1} minHeight={0} title=" Text ">
      <textarea id="editor-text" ref={editor} flexGrow={1} width="100%" initialValue="" wrapMode="word" backgroundColor="#14232c" focusedBackgroundColor="#14232c" textColor="#eee9dc" onContentChange={()=>setText(editor.current?.plainText??"")}/>
    </box>
    <text height={1} fg="#85ddca">{busy?"Working…":status} · {dirty?"Modified":"Unmodified"} · {text.split("\n").length} lines · {new TextEncoder().encode(text).length} bytes</text>
    <text height={1} fg="#718b99">Alt+F File · Ctrl+O open · Ctrl+S save · Ctrl+Q quit</text>
    {(menu||dialog||confirm)&&<box position="absolute" left={0} top={2} width="100%" height="95%" onMouseDown={()=>{if(menu)closeMenu()}}/>}
    {menu&&<box id="editor-menu" position="absolute" left={1} top={2} width={28} height={7} border backgroundColor="#20353f" borderColor="#36545e">
      {labels.map((label,index)=><box height={1} key={label} paddingX={1} backgroundColor={item===index?"#294650":"#20353f"}
        onMouseOver={()=>{setItem(index);if(index!==3)setSubmenu(false)}} onMouseDown={()=>{setItem(index);activate(index)}}>
        <text fg="#eee9dc">{label}</text>
      </box>)}
    </box>}
    {menu&&submenu&&<box id="editor-recents" position="absolute" left={29} top={6} width={44} maxWidth="55%" height={Math.min(8,Math.max(1,recents.length))+2} border backgroundColor="#20353f" borderColor="#36545e">
      <scrollbox ref={recentScroll} flexGrow={1} minHeight={0}>
        {recents.length?recents.map((name,index)=><box key={name} height={1} flexShrink={0} paddingX={1} backgroundColor={recentIndex===index?"#294650":"#20353f"} onMouseOver={()=>setRecentIndex(index)} onMouseDown={()=>load(name)}>
          <text wrapMode="none" fg="#eee9dc">{name.split("/").pop()}  {name}</text>
        </box>):<text fg="#718b99">No recent files</text>}
      </scrollbox>
    </box>}
    {dialog&&<box position="absolute" left={2} top={3} width="90%" height={6} border backgroundColor="#20353f" borderColor="#85ddca" paddingX={1} title={dialog==="open"?" Open file ":" Save as "}>
      <input id="editor-path" ref={pathInput} width="100%" height={1} value={filename} onInput={setFilename} placeholder="File path…" backgroundColor="#294650" focusedBackgroundColor="#294650" textColor="#eee9dc"/>
      <box height={1} flexDirection="row" gap={2}>
        <text fg="#85ddca" onMouseDown={submit}>[Enter: {dialog==="open"?"open":"save"}]</text>
        <text fg="#85ddca" onMouseDown={()=>setDialog(null)}>[Esc: cancel]</text>
      </box>
    </box>}
    {confirm&&<box position="absolute" left={2} top={3} width="90%" height={5} border backgroundColor="#294650" borderColor="#85ddca" paddingX={1}>
      <text fg="#eee9dc">{confirm.label}</text>
      <box flexDirection="row" gap={2} height={1}>
        <text fg="#85ddca" onMouseDown={()=>{if(!busy)confirm.action()}}>[Enter: confirm]</text>
        <text fg="#85ddca" onMouseDown={()=>setConfirm(null)}>[Esc: cancel]</text>
      </box>
    </box>}
  </box>;
}
export async function testEditor(frame:()=>void,feed:(text:string)=>void){
  const host=globalThis as any;
  const pause=async()=>{await new Promise(resolve=>setTimeout(resolve,80));frame()};
  await pause();
  feed("Hello café");await pause();
  feed("\x1b[H");await pause();
  feed("\x1b[B");await pause();
  feed("\rSecond line");await pause();
  const node=[...Renderable.renderablesByNumber.values()].find(node=>node.id==="editor-text") as any;
  if(node.plainText!=="Hello café\nSecond line")throw new Error("Down on the last line must move to its end before Return");

  if(!host.__snapshot().includes("Modified"))throw new Error("Editor must track changes");
  feed("\x13");
  for(let i=0;i<100&&!host.__snapshot().includes("Saved");i++)await pause();
  if(!host.__snapshot().includes("Saved"))throw new Error("Editor save failed");
  feed(" extra");await pause();
  feed("\x11");await pause();
  if(!host.__snapshot().includes("Quit and discard"))throw new Error("Quit must protect unsaved changes");
  feed("\x1b");await pause();
  feed("\x13");
  for(let i=0;i<100&&!host.__snapshot().includes("Replace the existing");i++)await pause();
  if(!host.__snapshot().includes("Replace the existing"))throw new Error("Overwrite must ask before replacing a file");
  feed("\x1b");await pause();
  feed("\x0f");await pause();
  if(!host.__snapshot().includes("Open file"))throw new Error("Ctrl+O must open the path dialog");
  feed("\r");await pause();
  if(!host.__snapshot().includes("Discard unsaved"))throw new Error("Load must protect unsaved changes");
  feed("\r");await pause();
  if(!host.__snapshot().includes("Loaded")||host.__snapshot().includes("extra"))throw new Error("Editor load round trip failed");
  feed("\x1bf");await pause();
  if(!host.__snapshot().includes("Recent files"))throw new Error("Alt+F must open File menu");
  for(const arrow of ["\x1b[B","\x1b[B","\x1b[B","\x1b[C"]){feed(arrow);await pause()}
  if(![...Renderable.renderablesByNumber.values()].some(node=>node.id==="editor-recents"))throw new Error("Right arrow must open recent files");
  feed("\x1b[D");await pause();
  if([...Renderable.renderablesByNumber.values()].some(node=>node.id==="editor-recents"))throw new Error("Left arrow must close recents");
  for(const arrow of ["\x1b[C","\x1b[B","\x1b[A","\r"]){feed(arrow);await pause()}
  if(!host.__snapshot().includes("Loaded")||host.__snapshot().includes("Recent files"))throw new Error("Recent selection must load and close menus");
}
