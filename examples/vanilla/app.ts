import {createApplication,HeldKeys} from "quicktui/core";
import {InputRenderable} from "quicktui/widgets";
import {testApp} from "quicktui/testing";

const app=createApplication({keyboard:{mode:"realtime"}});
const panel=app.box({id:"panel",border:true,title:" 10 / Vanilla JavaScript ",padding:1,gap:1,height:"100%"});
const title=app.text({id:"title",content:"One terminal core. No React."});
const counter=app.text({id:"counter",content:"Count: 0"});
let updateStats=()=>{};
const input=app.create(InputRenderable,{id:"name",placeholder:"Type here; releases should not insert text",width:50,onCursorChange:()=>updateStats()});
const stats=app.text({id:"input-stats",content:"Characters: 0 · Words: 0 · Line 1, column 1",fg:"#90a6b8"});
updateStats=()=>{
 const text=input.value;
 const cursor=input.logicalCursor;
 stats.content=`Characters: ${Array.from(text).length} · Words: ${text.trim()?text.trim().split(/\s+/u).length:0} · Line ${cursor.row+1}, column ${cursor.col+1}`;
};
input.on("input",updateStats);
const help=app.text({id:"help",content:"Ctrl+K counts · type in the input · Ctrl+C exits"});
app.root.add(panel);panel.add(title);panel.add(counter);panel.add(input);panel.add(stats);panel.add(help);
const spacer=app.box({id:"spacer",flexGrow:1});
const indicator=app.text({id:"keypress",content:"Key: none · held: none",fg:"#90a6b8",flexShrink:0});
panel.add(spacer);panel.add(indicator);
const held=new HeldKeys();
app.onInputReset(event=>{held.reset(event.reason);indicator.content=`Input reset: ${event.reason} · held: none`});
app.onKey(event=>{
 held.update(event);held.drainEdges();
 const modifiers=[event.ctrl&&"Ctrl",event.option&&"Alt",event.shift&&"Shift",event.super&&"Super"].filter(Boolean);
 indicator.content=`Key: ${[...modifiers,event.name].join("+")} · ${event.kind} · ${event.legacy?"legacy":"kitty"} · held: ${[...held.held].join(" ")||"none"}`;
 // Observe without consuming: normal input and the counter still receive keys.
});
input.focus();
let count=0;
app.onKey(event=>{
 if(event.ctrl&&event.name==="c"&&event.kind!=="release"){app.quit();return true}
 if(event.ctrl&&event.name==="k"){
  if(event.kind==="press")counter.content=`Count: ${++count}`;
  return true;
 }
});

testApp(async ui=>{
 await ui.resize(80,24);
 if(!ui.snapshot().includes("No React"))throw Error("Vanilla tree missing");
 await ui.input("\x1b[107;5u\x1b[107;5:2u\x1b[107;5:3u");
 if(!ui.snapshot().includes("Count: 1"))throw Error("Counter event routing failed");
 await ui.input("\x1b[97;;97u\x1b[97;1:2;97u\x1b[97;1:3u");
 if(!ui.snapshot().includes("Key: a · release · kitty · held: none"))throw Error("Key indicator missing release");
 if(input.value!=="aa")throw Error(`Widget press/repeat/release failed: ${input.value}`);
 await ui.input(" ");
 if(input.value!=="aa ")throw Error("Space was consumed instead of inserted");
 let calls=0;const off=app.onKey(()=>{calls++});off();await ui.input("b");
 if(!ui.snapshot().includes("Characters: 4 · Words: 2 · Line 1, column 5"))throw Error("Input statistics incorrect");
 await ui.input("\x1b[D");
 if(!ui.snapshot().includes("Line 1, column 4"))throw Error("Cursor statistic did not follow navigation");
 if(calls!==0)throw Error("Unsubscription failed");
 panel.insertBefore(help,title);
 panel.remove(counter);counter.destroyRecursively();
 await ui.input("");
 if(ui.snapshot().includes("Count: 1"))throw Error("Removed node still rendered");
});
