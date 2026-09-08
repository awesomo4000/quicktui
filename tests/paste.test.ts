import {test,expect} from "bun:test";
import {StdinParser} from "../vendor/opentui/packages/core/src/lib/stdin-parser";
const start="\x1b[200~",end="\x1b[201~",encoder=new TextEncoder();
function collect(chunks:Uint8Array[],limit=1024){
 let rejected=0;const events:any[]=[];
 const p=new StdinParser({armTimeouts:false,maxPasteBytes:limit,onPasteRejected:()=>rejected++});
 for(const chunk of chunks){p.push(chunk);p.drain(e=>events.push(e));}
 p.destroy();return {events,rejected};
}
test("literal paste survives every byte split, including UTF-8 and markers",()=>{
 const body="/run\nλ café 日本語 👩‍💻\nq\x1b[A";
 const bytes=encoder.encode(start+body+end+"z");
 for(let i=0;i<=bytes.length;i++){
  const {events,rejected}=collect([bytes.slice(0,i),bytes.slice(i)]);
  expect(rejected).toBe(0);expect(events.map(e=>e.type)).toEqual(["paste","key"]);
  expect(new TextDecoder().decode(events[0].bytes)).toBe(body);expect(events[1].key.name).toBe("z");
 }
});
test("seeded packet boundaries preserve repeated paste ordering",()=>{
 let seed=0x1234abcd;const next=()=>{seed^=seed<<13;seed^=seed>>>17;seed^=seed<<5;return seed>>>0};
 const text=Array.from({length:100},(_,i)=>start+`/${i}\n世界`+end).join("");
 const bytes=encoder.encode(text),chunks=[];
 for(let i=0;i<bytes.length;){const n=1+next()%31;chunks.push(bytes.slice(i,i+n));i+=n;}
 const {events}=collect(chunks);expect(events.length).toBe(100);
 events.forEach((e,i)=>expect(new TextDecoder().decode(e.bytes)).toBe(`/${i}\n世界`));
});
test("oversized paste is discarded through a split terminator, never keys",()=>{
 const {events,rejected}=collect([encoder.encode(start),...Array.from({length:100},()=>encoder.encode("q\n".repeat(64))),encoder.encode(end.slice(0,3)),encoder.encode(end.slice(3)+"a")],128);
 expect(rejected).toBe(1);expect(events.length).toBe(1);expect(events[0].key.name).toBe("a");
});
test("limit is bytes, exact limit succeeds, unfinished paste is discarded on reset",()=>{
 expect(collect([encoder.encode(start+"é".repeat(64)+end)],128).events.length).toBe(1);
 expect(collect([encoder.encode(start+"é".repeat(65)+end)],128).rejected).toBe(1);
 const p=new StdinParser({armTimeouts:false});p.push(encoder.encode(start+"q\n"));
 p.reset();p.push(encoder.encode("a"));const events:any[]=[];p.drain(e=>events.push(e));
 expect(events.length).toBe(1);expect(events[0].key.name).toBe("a");p.destroy();p.destroy();
});
