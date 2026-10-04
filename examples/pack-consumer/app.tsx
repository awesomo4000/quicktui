import React from "react";
import {mountApp,quit} from "quicktui";
import {testApp} from "quicktui/testing";
function App(){
 const editor=React.useRef<any>(null);
 React.useEffect(()=>{editor.current?.focus()},[]);
 return <box border title=" Embedded pack app " padding={1} flexDirection="column" height="100%">
  <text>Type here. Q is ordinary text. Ctrl+C quits.</text>
  <textarea ref={editor} initialValue="" flexGrow={1} width="100%" />
 </box>;
}
mountApp(App,{
 onKey(key){if(key.ctrl&&key.name==="c"){quit();return true;}},
});
testApp(async ui=>{
 if ("__loaderHost" in globalThis || "__sucrase" in globalThis) throw Error("Source loader exposed");
 // This target is created only AFTER packaging by the regression test.
 // A filesystem fallback would load it successfully and fail this assertion.
 const absent = "./not-in-pack.txt";
 let rejected = false;
 try { await import(absent); } catch { rejected = true; }
 if (!rejected) throw Error("Missing module escaped the pack");

 await ui.input("q");
 await ui.input("\x1b[200~hello\n世界\x1b[201~");
 if(!ui.snapshot().includes("qhello"))throw Error("Typing/paste did not render");
 await ui.resize(64,20);
 if(!ui.snapshot().includes("世界"))throw Error("Resize lost content");
});
