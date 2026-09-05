import { Buffer } from "../../vendor/js/node_modules/buffer";
import { EventEmitter } from "../../vendor/js/node_modules/events";
declare const __host: {now():number,write(s:string):void,platform:string,arch:string,env:Record<string,string>};
Object.assign(globalThis,{Buffer});
class TextEncoder {
  encode(value = "") { return Uint8Array.from(Buffer.from(String(value),"utf8")); }
  encodeInto(value:string,destination:Uint8Array) {
    let read=0,written=0;
    for(const char of value){const bytes=this.encode(char);if(written+bytes.length>destination.length)break;destination.set(bytes,written);written+=bytes.length;read+=char.length}
    return {read,written};
  }
}
class TextDecoder {
  constructor(label="utf-8",options:any={}) { if(!["utf-8","utf8"].includes(label.toLowerCase())||options.fatal) throw new Error("Only nonfatal UTF-8 decoding is supported"); }
  decode(value:any=new Uint8Array(),options:any={}) {if(options.stream)throw new Error("Streaming decoding is not supported"); return Buffer.from(value.buffer??value,value.byteOffset??0,value.byteLength).toString("utf8");}
}
const process = Object.assign(new EventEmitter(),{env:__host.env,arch:__host.arch,platform:__host.platform,versions:{quickjs:"2026-06-04"},cwd:()=>".",nextTick:(fn:Function,...args:any[])=>Promise.resolve().then(()=>fn(...args)),hrtime:Object.assign(()=>{const n=__host.now();return [Math.floor(n/1000),Math.floor(n%1000*1e6)]},{bigint:()=>BigInt(Math.floor(__host.now()*1e6))})});
// NativeImage inputs only need cancellation state; network/file loading is excluded.
class AbortController {
  signal={aborted:false,reason:undefined as unknown,throwIfAborted(){if(this.aborted)throw this.reason}};
  abort(reason:unknown=new Error("Operation aborted")){this.signal.aborted=true;this.signal.reason=reason}
}
let nextTimer=1;
const timers=new Map<number,{due:number,fn:Function,args:any[],interval?:number}>();
Object.assign(globalThis,{TextEncoder,TextDecoder,AbortController,process,performance:{now:__host.now},
  console:Object.fromEntries(["log","info","warn","error","debug"].map(name=>[name,(...args:any[])=>__host.write(args.map(String).join(" ")+"\n")])),
  queueMicrotask:(fn:Function)=>Promise.resolve().then(()=>fn()),
  setTimeout:(fn:Function,delay=0,...args:any[])=>{const id=nextTimer++;timers.set(id,{due:__host.now()+Math.max(0,Number(delay)||0),fn,args});return id},
  clearTimeout:(id:number)=>timers.delete(id),
  setInterval:(fn:Function,delay=0,...args:any[])=>{const id=nextTimer++;const interval=Math.max(1,Number(delay)||0);timers.set(id,{due:__host.now()+interval,fn,args,interval});return id},
  clearInterval:(id:number)=>timers.delete(id),
});
Object.assign(globalThis,{__timers:{
  tick(){const now=__host.now();let count=0;for(const [id,t] of [...timers])if(t.due<=now&&timers.delete(id)){if(t.interval)timers.set(id,{...t,due:now+t.interval});t.fn(...t.args);if(++count===128)break}},
  delay(){if(!timers.size)return -1;return Math.max(0,Math.ceil(Math.min(...[...timers.values()].map(t=>t.due))-__host.now()))},
  clear(){timers.clear()},
}});
