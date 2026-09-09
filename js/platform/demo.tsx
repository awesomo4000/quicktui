/** React adapter for the shared terminal application runtime. */
import React,{useEffect} from "../../vendor/js/node_modules/react";
import ReactReconciler from "../../vendor/js/node_modules/react-reconciler";
import {hostConfig} from "../../vendor/opentui/packages/react/src/reconciler/host-config";
import {mountApplication,type ApplicationOptions} from "./application";
export {keys,copyTerminalText,interceptKeys,graphicsState} from "./application";
export interface AppOptions extends ApplicationOptions {onCaughtError?:(error:unknown)=>void;}
export function mountApp(App:()=>React.ReactNode,options:AppOptions={}){return mountReact(App,options,false)}
export function mountDemo(App:()=>React.ReactNode,options:AppOptions={}){return mountReact(App,options,true)}
function mountReact(App:()=>React.ReactNode,options:AppOptions,shortcuts:boolean){
 const reconciler=ReactReconciler(hostConfig);
 const report=(error:unknown)=>{throw error};
 let container:any,effectMounted=false;
 function Mounted(){
  useEffect(()=>{effectMounted=true;return()=>{effectMounted=false}},[]);
  return <App/>;
 }
 const app=mountApplication({
  batch:work=>reconciler.flushSyncFromReconciler(work),
  mount(root){
   container=reconciler.createContainer(root,1,null,false,null,"",report,options.onCaughtError??report,report,()=>{});
   reconciler.updateContainerSync(<Mounted/>,container,null,null);
   reconciler.flushSyncWork();reconciler.flushPassiveEffects();
  },
  unmount(){if(container){reconciler.updateContainerSync(null,container,null,null);reconciler.flushSyncWork();reconciler.flushPassiveEffects()}},
  inspect:()=>({effectMounted}),
 },options,shortcuts);
 return {quit:app.quit,snapshot:app.snapshot};
}
