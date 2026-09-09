import {KeyEvent} from "../vendor/opentui/packages/core/src/lib/KeyHandler";
export interface KeyboardOptions {
 mode?:"text"|"realtime";
 disambiguate?:boolean; events?:boolean; alternateKeys?:boolean; allKeysAsEscapes?:boolean; reportText?:boolean;
}
export function keyboardFlags(options:KeyboardOptions={}){
 const defaults=options.mode==="realtime"?31:5;
 return ["disambiguate","events","alternateKeys","allKeysAsEscapes","reportText"].reduce((flags,name,i)=>{
  const value=options[name as keyof KeyboardOptions];return value===undefined?flags:value?flags|(1<<i):flags&~(1<<i);
 },defaults);
}
export type InputResetReason="startup"|"resume"|"reload"|"focus-loss"|"endpoint-closed"|"shutdown"|"overflow"|"manual";
export type InputReset={reason:InputResetReason};
export type KeyboardCapabilities={requestedFlags:number,protocol:"unknown"|"legacy"|"kitty",releases:"unknown"|"observed",focus:"unknown"|"observed",modifierEvents:"unknown"|"observed",heldStateAvailable:boolean};
export class AppKeyEvent extends KeyEvent {
 kind:"press"|"repeat"|"release";
 identity:string;
 text:string|undefined;
 associatedText:string|undefined;
 legacy:boolean;
 trackable:boolean;
 constructor(key:ConstructorParameters<typeof KeyEvent>[0],public receivedAt:number,public sequenceNumber:number,public dispatchedAt:number){
  super(key);this.kind=key.eventType==="release"?"release":key.repeated?"repeat":"press";
  const code=key.raw.match(/^\x1b\[(\d+)/)?.[1];
  this.identity=key.source==="kitty"?`kitty:${key.code??(key.raw.endsWith("u")?code:undefined)??key.name}`:`legacy:${key.name.toLowerCase()}`;
  this.legacy=key.source!=="kitty";this.trackable=!this.legacy&&code!=="0";
  // sequence is the parser's decoded text for printable Kitty keys, raw CSI otherwise.
  this.associatedText=/^\x1b\[[\d:]+;[\d:]*;[\d:]+u$/.test(key.raw)?key.sequence:undefined;
  this.text=this.kind==="release"?undefined:this.associatedText??(this.kind!=="release"&&!key.ctrl&&!key.super&&!key.hyper&&!key.option&&!key.sequence.startsWith("\x1b")?key.sequence:undefined);
 }
}
export type KeyEdge={identity:string,name:string,kind:"press"|"release"};
/** For protocols that actually supply releases. No timeout-based fake releases. */
export class HeldKeys {
 private down=new Map<string,string>();private edges:KeyEdge[]=[];
 constructor(private onReset?:(event:InputReset)=>void,private maxEdges=256){}
 has(name:string){return [...this.down.values()].includes(name)}
 get held(){return new Set(this.down.keys())}
 update(event:AppKeyEvent){
  if(!event.trackable)return;
  if(event.kind==="release"){
   const name=this.down.get(event.identity);if(name===undefined)return;
   this.down.delete(event.identity);this.push({identity:event.identity,name,kind:"release"});
  }else if(event.kind==="press"&&!this.down.has(event.identity)){
   if(this.down.size>=this.maxEdges){this.reset("overflow");return;}
   this.down.set(event.identity,event.name);this.push({identity:event.identity,name:event.name,kind:"press"});
  }
 }
 private push(edge:KeyEdge){if(this.edges.length>=this.maxEdges){this.reset("overflow");return}this.edges.push(edge)}
 drainEdges(){const result=this.edges;this.edges=[];return result}
 reset(reason:InputResetReason="manual"){this.down.clear();this.edges=[];this.onReset?.({reason})}
}
type KeyboardSubscription={key:(event:AppKeyEvent)=>boolean|void,reset?:(event:InputReset)=>void};
const subscriptions=new Set<KeyboardSubscription>();
/** Internal subscription channel owned by this JS runtime. */
export function subscribeKeyboard(key:KeyboardSubscription["key"],reset?:KeyboardSubscription["reset"]){
 const subscription={key,reset};subscriptions.add(subscription);
 return ()=>{subscriptions.delete(subscription)};
}
export function resetKeyboardSubscriptions(event:InputReset){
 for(const subscription of [...subscriptions])if(subscriptions.has(subscription))subscription.reset?.(event);
}
/** Shared application routing: consumption happens before focused-widget fallback. */
export function dispatchAppKey(event:AppKeyEvent,onKey:((event:AppKeyEvent)=>boolean|void)|undefined,emit:(name:"keypress"|"keyrelease",event:AppKeyEvent)=>void){
 if(onKey?.(event)||event.defaultPrevented||event.propagationStopped)return;
 for(const subscription of [...subscriptions]){
  if(!subscriptions.has(subscription))continue;
  if(subscription.key(event)||event.defaultPrevented||event.propagationStopped)return;
 }
 emit(event.kind==="release"?"keyrelease":"keypress",event);
}
