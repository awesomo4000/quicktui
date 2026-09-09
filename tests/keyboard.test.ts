import {test,expect} from "bun:test";
import {AppKeyEvent,HeldKeys,keyboardFlags,dispatchAppKey} from "../js/keyboard";
import {StdinParser} from "../vendor/opentui/packages/core/src/lib/stdin-parser";
import {PlatformGame} from "../js/game-model";
const enc=new TextEncoder();
function events(text:string,split=0){
 const parser=new StdinParser({armTimeouts:false});const result:AppKeyEvent[]=[];
 const bytes=enc.encode(text);
 for(const chunk of [bytes.slice(0,split),bytes.slice(split)]){parser.push(chunk);parser.drain(e=>{if(e.type==="key")result.push(new AppKeyEvent(e.key,10,result.length+1,11))})}
 parser.destroy();return result;
}
test("keyboard flags are opt-in with explicit overrides",()=>{
 expect(keyboardFlags()).toBe(5);expect(keyboardFlags({mode:"realtime"})).toBe(31);
 expect(keyboardFlags({mode:"realtime",reportText:false})).toBe(15);
});
test("CSI-u identity, events, modifiers and text survive every split",()=>{
 const wire="\x1b[100;1:1u\x1b[32;1:1u\x1b[32;1:2u\x1b[32;1:3u\x1b[100;2:3u\x1b[97;9:1;233u";
 const expected=events(wire);
 for(let i=0;i<=enc.encode(wire).length;i++)expect(events(wire,i)).toEqual(expected);
 expect(expected.map(e=>e.kind)).toEqual(["press","press","repeat","release","release","press"]);
 expect(expected[5].super).toBe(true);expect(expected[5].option).toBe(false);expect(expected[5].associatedText).toBe("é");
});
test("overlapping keys, short taps, modifier changes and reset never leave keys stuck",()=>{
 const tracker=new HeldKeys();const feed=(s:string)=>events(s).forEach(e=>tracker.update(e));
 feed("\x1b[100;1u\x1b[32;1u\x1b[32;1:2u\x1b[32;1:3u");
 expect(tracker.has("d")).toBe(true);expect(tracker.has("space")).toBe(false);
 expect(tracker.drainEdges().filter(e=>e.name==="space"&&e.kind==="press")).toHaveLength(1);
 feed("\x1b[100;2:3u");expect(tracker.held.size).toBe(0);
 feed("\x1b[100;1u\x1b[97;1u\x1b[100;1:3u");expect(tracker.has("a")).toBe(true);
 tracker.reset("focus-loss");feed("\x1b[97;1:2u\x1b[97;1:3u");expect(tracker.held.size).toBe(0);
 feed("\x1b[32;1u\x1b[32;1u\x1b[32;1:3u");expect(tracker.drainEdges()).toHaveLength(2);
});
test("held tracker overflow resets explicitly and legacy input never fabricates holds",()=>{
 const reasons:string[]=[];const t=new HeldKeys(e=>reasons.push(e.reason),2);
 events("abc").forEach(e=>t.update(e));expect(t.held.size).toBe(0);
 events("\x1b[97;1u\x1b[98;1u\x1b[99;1u").forEach(e=>t.update(e));
 expect(reasons).toEqual(["overflow"]);expect(t.held.size).toBe(0);
});
test("platform physics supports short hop, walls, pits and a reachable exit",()=>{
 const full=new PlatformGame(),short=new PlatformGame();
 full.step(1/60,0,true,false);short.step(1/60,0,true,false);short.step(1/60,0,false,true);
 for(let i=0;i<12;i++){full.step(1/60,0,false,false);short.step(1/60,0,false,false)}
 expect(full.y).toBeLessThan(short.y);
 const game=new PlatformGame();for(let i=0;i<120;i++)game.step(1/60,1,false,false);
 expect(game.x).toBeLessThan(19);
 game.x=24;game.y=11;game.grounded=false;
 for(let i=0;i<120;i++)game.step(1/60,0,false,false);
 expect(game.deaths).toBeGreaterThan(0);
 // Play the full course with jumps ahead of each obstacle.
 game.reset();let jumped=new Set<number>();
 for(let i=0;i<1500&&!game.won;i++){
  const targets=[14,20,27,34,42];const target=targets.find(x=>game.x>=x&&!jumped.has(x));
  const jump=target!==undefined&&game.grounded;if(jump)jumped.add(target!);
  game.step(1/60,1,jump,false);
 }
 expect(game.won).toBe(true);
});
test("parser input overflow reports loss of a protocol unit",()=>{
 let resets=0;const p=new StdinParser({armTimeouts:false,maxPendingBytes:16,onInputOverflow:()=>resets++});
 p.push(enc.encode("\x1b]"+"x".repeat(2048)));p.drain(()=>{});p.destroy();expect(resets).toBeGreaterThan(0);
});

test("consumption and release routing never turn key-up into text",()=>{
 const emitted:string[]=[];
 const sequence=events("\x1b[97;1u\x1b[97;1:2u\x1b[97;1:3u");
 for(const e of sequence)dispatchAppKey(e,undefined,name=>emitted.push(name));
 expect(emitted).toEqual(["keypress","keypress","keyrelease"]);
 dispatchAppKey(sequence[0],()=>true,()=>{throw Error("Consumed key leaked")});
 dispatchAppKey(sequence[1],e=>e.preventDefault(),()=>{throw Error("Prevented key leaked")});
 const arrows=events("\x1b[1;1:1C\x1b[1;1:1D");
 expect(arrows[0].identity).not.toBe(arrows[1].identity);
});

test("component subscriptions preserve widget routing and clean up",async()=>{
 const {subscribeKeyboard,resetKeyboardSubscriptions}=await import("../js/keyboard");
 const calls:string[]=[];
 const off=subscribeKeyboard(e=>{calls.push(e.kind)},e=>calls.push(e.reason));
 for(const event of events("\x1b[97;1u\x1b[97;1:2u\x1b[97;1:3u"))dispatchAppKey(event,undefined,name=>calls.push(name));
 expect(calls).toEqual(["press","keypress","repeat","keypress","release","keyrelease"]);
 resetKeyboardSubscriptions({reason:"focus-loss"});expect(calls.at(-1)).toBe("focus-loss");
 off();calls.length=0;
 dispatchAppKey(events("a")[0],undefined,name=>calls.push(name));
 resetKeyboardSubscriptions({reason:"reload"});expect(calls).toEqual(["keypress"]);
 const consume=subscribeKeyboard(()=>true);
 const later=subscribeKeyboard(()=>{throw Error("Consumed event reached later hook")});
 dispatchAppKey(events("a")[0],undefined,()=>{throw Error("Consumed event reached widget")});
 consume();later();
});

test("either foot supports a jump at platform edges",()=>{
 for(const [x,direction] of [[20.6,1],[18.6,-1]]){
  const game=new PlatformGame();game.x=x;game.y=9.1;game.grounded=true;
  game.step(1/60,0,false,false);
  expect(game.grounded).toBe(true);
  expect(game.y).toBeCloseTo(9.1);
  game.step(1/60,direction,true,false);
  expect(game.vy).toBeLessThan(0);
  expect(game.y).toBeLessThan(9.1);
  expect(direction*(game.x-x)).toBeGreaterThan(0);
 }
 const game=new PlatformGame();game.x=21;game.y=9.1;
 game.step(1/60,0,false,false);expect(game.grounded).toBe(false);
});


test("first platform launches across the first pit",()=>{
 const game=new PlatformGame();game.x=20;game.y=9.1;game.grounded=true;
 game.step(1/60,1,true,false);
 for(let i=0;i<90&&!game.grounded&&game.deaths===0;i++)game.step(1/60,1,false,false);
 expect(game.deaths).toBe(0);expect(game.grounded).toBe(true);
 expect(game.x).toBeGreaterThanOrEqual(27);
});
