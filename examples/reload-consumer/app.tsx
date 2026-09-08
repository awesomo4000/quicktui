import React from "react";
import {mountApp,quit,requestReload,getReloadState,getReloadInfo} from "quicktui";
const saved=getReloadState({version:1,draft:""});
if(saved.version!==1||typeof saved.draft!=="string")throw Error("Unsupported snapshot");
const info=getReloadInfo();
const editor=React.createRef<any>();
function App(){
 React.useEffect(()=>{editor.current?.focus()},[]);
 return <box border title=" Independent reload app " padding={1} flexDirection="column" height="100%">
  <text>Type a draft. Ctrl+R reloads. Ctrl+C quits.</text>
  <text>{info.generation===1?"Initial runtime":"Restored draft: "+saved.draft}</text>
  <text>Generation {info.generation} {info.notice}</text>
  <textarea ref={editor} initialValue={saved.draft} flexGrow={1} width="100%" />
 </box>;
}
mountApp(App,{
 exportState:()=>({version:1,draft:editor.current?.plainText??saved.draft}),
 onKey(key){
  if(key.ctrl&&key.name==="c"){quit();return true}
  if(key.ctrl&&key.name==="r"){requestReload();return true}
 },
});
