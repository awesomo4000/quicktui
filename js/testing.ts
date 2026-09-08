/** Explicit test driver, intended for runApp(..., .{.headless=true}). */
declare const __host:{headless:boolean};
const host=globalThis as any;
export function testApp(test:(driver:{input(text:string):Promise<void>;resize(width:number,height:number):Promise<void>;snapshot():string})=>Promise<void>){
 if(!__host.headless)return;
 const flush=async()=>{for(let i=0;i<4;i++){host.__tick();await Promise.resolve();host.__frame();}};
 host.__selfTest=()=>test({
  async input(text){host.__input(new TextEncoder().encode(text).buffer);await flush()},
  async resize(width,height){host.__resize(width,height);await flush()},
  snapshot:()=>host.__snapshot(),
 });
}
