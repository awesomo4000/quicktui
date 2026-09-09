/** Framework-neutral application API. No React imports or reconciler. */
import {mountApplication,type ApplicationOptions} from "./platform/application";
import {subscribeKeyboard,type AppKeyEvent,type InputReset} from "./keyboard";
import {Renderable} from "../vendor/opentui/packages/core/src/Renderable";
import {BoxRenderable,type BoxOptions} from "../vendor/opentui/packages/core/src/renderables/Box";
import {TextRenderable,type TextOptions} from "../vendor/opentui/packages/core/src/renderables/Text";
export {mountApplication,type ApplicationAdapter,type ApplicationOptions} from "./platform/application";
export * from "./services";
export {HeldKeys,AppKeyEvent,type KeyboardOptions,type KeyboardCapabilities,type InputReset,type InputResetReason} from "./keyboard";

/** Construct one application in the current native host runtime. The host drives the loop. */
export function createApplication(options:ApplicationOptions={}){
 const nodes=new Set<Renderable>(),subscriptions=new Set<()=>void>();
 const app=mountApplication({
  mount(){},
  unmount(){
   for(const off of subscriptions)off();subscriptions.clear();
   for(const node of nodes)if(!node.isDestroyed)node.destroyRecursively();nodes.clear();
  },
 },options);
 function trackSubscription(off:()=>void){
  subscriptions.add(off);return ()=>{subscriptions.delete(off);off()};
 }
 function create<C extends new(context:any,options:any)=>Renderable>(Widget:C,props:ConstructorParameters<C>[1]):InstanceType<C>{
  const node=new Widget(app.context,props);nodes.add(node);node.once("destroyed",()=>nodes.delete(node));return node as InstanceType<C>;
 }
 return {
  root:app.root,quit:app.quit,snapshot:app.snapshot,
  create,
  box:(props:BoxOptions={})=>create(BoxRenderable,props),
  text:(props:TextOptions={})=>create(TextRenderable,props),
  onKey:(handler:(event:AppKeyEvent)=>boolean|void)=>trackSubscription(subscribeKeyboard(handler)),
  onInputReset:(handler:(event:InputReset)=>void)=>trackSubscription(subscribeKeyboard(()=>{},handler)),
  onResize(handler:(width:number,height:number)=>void){
   app.context.on("resize",handler);return trackSubscription(()=>app.context.off("resize",handler));
  },
 };
}
