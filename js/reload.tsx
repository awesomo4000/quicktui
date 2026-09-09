import React,{useEffect,useState} from "../vendor/js/node_modules/react";
import {mountApp,keys} from "./platform/demo";
import {getReloadState,getReloadInfo,requestReload} from "./app";
declare const __host:{generation:number,reloadState:string,reloadNotice:string,headless:boolean,tryPostMessage(text:string):string,requestReload(source?:string):void,quit():void};
const host=globalThis as any;
if(host.__reloadCanary!==undefined)throw Error("Previous runtime globals survived");
host.__reloadCanary=__host.generation;
const saved=getReloadState({count:0,round:0,draft:"",caret:0,selection:null as {start:number,end:number}|null,scrollX:0,scrollY:0});
const editor=React.createRef<any>();
function exportState(){
  const node=editor.current,view=node.editorView.getViewport();
  return {...saved,draft:node.plainText,caret:node.cursorOffset,selection:node.getSelection(),scrollX:view.offsetX,scrollY:view.offsetY};
}
if(!Number.isInteger(saved.count)||!Number.isInteger(saved.round))throw Error("Invalid demo snapshot");
Object.assign(globalThis,{
  __reloadNotice:(notice:string)=>keys.emit("reload-notice",notice),
});
function App(){
  const [count,setCount]=useState(saved.count),[scratch,setScratch]=useState(0);
  const [notice,setNotice]=useState(getReloadInfo().notice||"Ready. Type a draft, then press Ctrl+R.");
  const [events,setEvents]=useState(0);
  useEffect(()=>{
    const node=editor.current;
    node.focus();node.cursorOffset=saved.caret;
    if(saved.selection)node.setSelection(saved.selection.start,saved.selection.end);
    const key=(name:string)=>{
      if(name==="g"){saved.count++;setCount(saved.count)}
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
    <text fg="#c4ced4">Ctrl+G saved counter · Ctrl+U unsaved · Ctrl+R reload</text>
    <text fg="#c4ced4">Ctrl+B broken bundle · Ctrl+C exit · text and paste stay literal</text>
    <textarea id="reload-draft" ref={editor} initialValue={saved.draft} border title=" Retained draft, caret and selection " height={8} minHeight={3} flexGrow={1} flexShrink={1} width="100%"
 />
    <text fg="#79909c">Same native process · new JS heap · native events this generation: {events}</text>
    <text fg={accent}>{notice}</text>
    <text fg="#79909c">Experimental trusted reload · bundled source reused on R · no file watcher in 06b yet</text>
  </box>;
}
mountApp(App,{
  exportState,
  onFirstLayout(){
    const node=editor.current,view=node.editorView.getViewport();
    node.editorView.setViewport(saved.scrollX,saved.scrollY,view.width,view.height,false);
  },
  onKey(key){
    if(key.ctrl&&key.name==="c"){__host.quit();return true}
    if(key.ctrl&&["g","u","r","b"].includes(key.name)){keys.emit("key",key.name);return true}
  },
});
// One headless sequence spans eight fresh runtimes, including syntax/evaluation
// failure and a bounded infinite-loop candidate. This cannot be a Promise owned
// by the first runtime, because replacement intentionally destroys that Promise.
if(__host.headless){
  const literal="/run\n界 café 👩‍💻\nq\n"+Array.from({length:30},(_,i)=>`line ${i}`).join("\n");
  if(saved.round===0){
    setTimeout(()=>host.__input(new TextEncoder().encode("\x1b[200~"+literal.slice(0,5)).buffer),20);
    setTimeout(()=>{
      if(__host.generation!==1)throw Error("Reload retired a partial paste");
      host.__input(new TextEncoder().encode(literal.slice(5)+"\x1b[201~").buffer);
      editor.current.cursorOffset=3;editor.current.setSelection(1,3);
      const view=editor.current.editorView.getViewport();
      editor.current.editorView.setViewport(0,3,view.width,view.height,false);editor.current.requestRender();
    },180);
  }
  setTimeout(()=>{
    if(!host.__snapshot().includes("Unsaved counter: 0"))throw Error("Unsaved state survived replacement");
    keys.emit("key","u");
  },40);
  setTimeout(()=>{
    if(saved.round>0){
      if(editor.current.plainText!==literal)throw Error("Fragmented paste lost or duplicated text");
      if(editor.current.scrollY!==3)throw Error(`Scroll offset lost: saved ${saved.scrollY}, actual ${editor.current.scrollY}`);
      if(editor.current.cursorOffset!==3||JSON.stringify(editor.current.getSelection())!==JSON.stringify({start:1,end:3}))throw Error("Caret or selection lost");
    }
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
    if(saved.round!==1&&__host.tryPostMessage("late")!=="closed")throw Error("Send crossed reload barrier");
  },100);
}
