import {aiHelpPrompt,aiHelpTitles} from "./paint-ai-help";
import {cyclePalette,testCycle} from "./paint-cycle";
import "./paint-canvas";
import React,{useEffect,useRef,useState} from "../vendor/js/node_modules/react";
import {InputRenderable} from "../vendor/opentui/packages/core/src/renderables/Input";
import {Renderable} from "../vendor/opentui/packages/core/src/Renderable";
import {mountDemo,interceptKeys,keys,graphicsState,copyTerminalText} from "./platform/demo";
import {PaintCanvas} from "./paint-canvas";
import {Painting,palette,Tool,testPainting,testPaintingResize,testPaintingAlpha,testPaintingPalette,TRANSPARENT} from "./paint-model";
declare const __host:{headless:boolean,postMessage(text:string):boolean,takeBuffer(id:number):ArrayBuffer|null,quit():void};
let pending:{resolve:(v:any)=>void,reject:(e:Error)=>void}|null=null;
Object.assign(globalThis,{__message(text:string){const reply=JSON.parse(text),waiter=pending;pending=null;if(reply.error)waiter?.reject(new Error(reply.error));else waiter?.resolve(reply)}});
function request(value:any):Promise<any>{return new Promise((resolve,reject)=>{if(pending){reject(new Error("Worker busy"));return}pending={resolve,reject};if(!__host.postMessage(JSON.stringify(value))){pending=null;reject(new Error("Worker busy"))}})}
const backgroundClick=(event:any)=>event.button===2||(event.button===0&&event.modifiers?.ctrl);
const tools:Tool[]=["pencil","brush","spray","fill"];
const labels=["1 Pencil","2 Paintbrush","3 Spray","4 Flood fill"];
function App(){
  const [painting]=useState(()=>new Painting()),canvas=useRef<PaintCanvas|null>(null);
  const palette=painting.palette;
  const [kitty,setKitty]=useState(graphicsState.confirmed),[pixelOutput,setPixelOutput]=useState(false);
  const [cycling,setCycling]=useState(false),[elapsed,setElapsed]=useState(0),[hover,setHover]=useState<number|null>(null);
  const elapsedRef=useRef(0);
  const displayPalette=cyclePalette(palette,painting.cycle,elapsed);
  const previewPalette=displayPalette.map((color,i)=>i===hover?"#ffffff":color);
  const [tool,setTool]=useState<Tool>("pencil"),[size,setSize]=useState(2),[fg,setFg]=useState(0),[bg,setBg]=useState(1);
  const [revision,refresh]=useState(0),[file,setFile]=useState("painting.tpaint"),[saved,setSaved]=useState(()=>painting.serialize());
  const [busy,setBusy]=useState(true),[status,setStatus]=useState("Ready"),[position,setPosition]=useState("");
  const [openDialog,setOpenDialog]=useState(false),[openPath,setOpenPath]=useState("");
  const pathInput=useRef<InputRenderable|null>(null);
  const [helpOpen,setHelpOpen]=useState(false),[helpTopic,setHelpTopic]=useState(0),[helpStatus,setHelpStatus]=useState("");
  const copyGuide=()=>setHelpStatus(copyTerminalText(aiHelpPrompt(helpTopic))?"Guide sent to terminal clipboard. Paste into your assistant.":"Clipboard unavailable. Read the skills/ folder in the project.");
  const [exportOpen,setExportOpen]=useState(false),[exportWidth,setExportWidth]=useState(960);
  const [confirm,setConfirm]=useState<{label:string,action:()=>void}|null>(null);
  const stroke=useRef<{point:{x:number,y:number}|null,color:number,tool:Tool,size:number}|null>(null);
  const dirty=painting.serialize()!==saved;
  const redraw=()=>refresh(value=>value+1);
  const end=()=>{stroke.current=null};
  const move=(event:any,paint=false)=>{
    const point=canvas.current!.point(event.x,event.y);
    canvas.current!.cursor=point;canvas.current!.requestRender();setPosition(point?`${point.x}, ${point.y}`:"");
    const active=stroke.current;
    if(paint&&active){
      if(point){const from=active.point??point;painting.line(from.x,from.y,point.x,point.y,active.color,active.size,active.tool);redraw()}
      active.point=point;
    }
  };
  const start=(event:any)=>{
    if(busy||confirm||exportOpen||helpOpen||openDialog||![0,2].includes(event.button))return;
    const point=canvas.current!.point(event.x,event.y);if(!point)return;
    painting.checkpoint();
    const color=backgroundClick(event)?bg:fg;
    if(tool==="fill"){painting.fill(point.x,point.y,color);redraw();return}
    stroke.current={point,color,tool,size};painting.stamp(point.x,point.y,color,size,tool);redraw();
  };
  const save=async(overwrite=false)=>{
    if(busy)return;end();setBusy(true);setConfirm(null);
    const text=painting.serialize();
    try{
      await request({op:"begin"});
      for(let i=0;i<text.length;i+=1024)await request({op:"append",text:text.slice(i,i+1024)});
      await request({op:"save",path:file,overwrite});setSaved(text);setStatus("Saved "+file);
    }catch(error){
      if((error as Error).message==="FileExists")setConfirm({label:"Replace "+file+"?",action:()=>void save(true)});
      else setStatus("Save failed: "+(error as Error).message);
    }finally{setBusy(false)}
  };
  const showOpen=()=>{end();setOpenPath(file);setOpenDialog(true)};
  const doLoad=async(path:string)=>{
    end();setOpenDialog(false);setConfirm(null);setBusy(true);
    try{const reply=await request({op:"load",path});const bytes=__host.takeBuffer(reply.id);if(!bytes)throw new Error("Missing painting");painting.load(new TextDecoder().decode(bytes));painting.undoStack=[];painting.redoStack=[];if(canvas.current)canvas.current.cursor=null;setFile(path);setSaved(painting.serialize());setCycling(false);elapsedRef.current=0;setElapsed(0);setStatus("Loaded "+path);redraw()}
    catch(error){setStatus("Open failed: "+(error as Error).message)}finally{setBusy(false)}
  };
  const submitOpen=()=>{const path=openPath;if(!path)return;setOpenDialog(false);if(dirty)setConfirm({label:"Discard unsaved changes and open "+path+"?",action:()=>void doLoad(path)});else void doLoad(path)};
  useEffect(()=>{if(openDialog&&!busy&&!confirm){pathInput.current?.focus();return()=>{pathInput.current?.blur()}}},[openDialog,busy,confirm]);
  const exportPath=(width:number)=>file.replace(/\.[^/.]+$/,"")+`-${width}.gif`;
  const exportGif=async(width=exportWidth,overwrite=false)=>{
    if(busy)return;end();setExportOpen(false);setBusy(true);setConfirm(null);
    const path=exportPath(width),text=painting.serialize();setStatus("Exporting GIF…");
    try{
      await request({op:"begin"});for(let i=0;i<text.length;i+=1024)await request({op:"append",text:text.slice(i,i+1024)});
      await request({op:"gif",path,width,overwrite});setStatus("Exported "+path);
    }catch(error){if((error as Error).message==="FileExists")setConfirm({label:"Replace "+path+"?",action:()=>void exportGif(width,true)});else setStatus("GIF export: "+(error as Error).message)}finally{setBusy(false)}
  };
  const clear=()=>{end();setConfirm({label:"Clear the canvas? You can undo this.",action:()=>{painting.checkpoint();painting.pixels.fill(bg);redraw();setConfirm(null)}})};
  const resize=()=>{end();const sizes=[[96,64],[192,128],[256,192]];const index=sizes.findIndex(([w,h])=>w===painting.width&&h===painting.height);const [w,h]=sizes[(index+1)%sizes.length];setConfirm({label:`Resize painting to ${w} × ${h}? Scales existing art; undoable.`,action:()=>{painting.resize(w,h);if(canvas.current)canvas.current.cursor=null;redraw();setConfirm(null)}})};
  const range=()=>{if(fg===TRANSPARENT||bg===TRANSPARENT||fg===bg){setStatus("Select two different opaque FG/BG colors for the range");return}painting.cycle={...painting.cycle,start:Math.min(fg,bg),end:Math.max(fg,bg)};elapsedRef.current=0;setElapsed(0);redraw()};
  const speed=(factor:number)=>{painting.cycle={...painting.cycle,stepMs:Math.max(40,Math.min(2000,Math.round(painting.cycle.stepMs*factor)))};redraw()};
  const reverse=()=>{painting.cycle={...painting.cycle,direction:-painting.cycle.direction};redraw()};
  useEffect(()=>{if(!cycling||busy||confirm||exportOpen||helpOpen||openDialog)return;let last=Date.now();const timer=setInterval(()=>{const now=Date.now();elapsedRef.current+=now-last;last=now;setElapsed(elapsedRef.current)},40);return()=>clearInterval(timer)},[cycling,busy,confirm,exportOpen,helpOpen,openDialog]);
  const quit=()=>{end();if(dirty)setConfirm({label:"Quit without saving your painting?",action:()=>__host.quit()});else __host.quit()};
  useEffect(()=>{const changed=(value:boolean)=>setKitty(value);keys.on("graphics",changed);return()=>{keys.off("graphics",changed)}},[]);
  useEffect(()=>{
    void request({op:"info"}).then(async reply=>{
      if(reply.path){setFile(reply.path);if(!__host.headless){const result=await request({op:"load",path:reply.path});const bytes=__host.takeBuffer(result.id);if(!bytes)throw new Error("Missing painting");painting.load(new TextDecoder().decode(bytes));painting.undoStack=[];setSaved(painting.serialize());redraw();setStatus("Loaded "+reply.path)}}
    }).catch(error=>setStatus("Open: "+error.message+" · blank canvas")).finally(()=>setBusy(false));
    const timer=setInterval(()=>{
      const active=stroke.current;
      if(active?.tool==="spray"&&active.point){painting.stamp(active.point.x,active.point.y,active.color,active.size,"spray");redraw()}
    },45);
    return()=>{clearInterval(timer);stroke.current=null};
  },[]);
  useEffect(()=>{
    interceptKeys(event=>{
      const key=event.name.toLowerCase();
      if(busy)return true;
      if(openDialog){if(key==="escape")setOpenDialog(false);else if(key==="return")submitOpen();else pathInput.current?.handleKeyPress(event);return true}
      if(helpOpen){if(key==="escape"||key==="h")setHelpOpen(false);if(key==="1"||key==="2"){setHelpTopic(Number(key)-1);setHelpStatus("")}if(key==="c")copyGuide();return true}
      if(exportOpen){if(key==="escape")setExportOpen(false);if(key==="left"||key==="right")setExportWidth(w=>{const sizes=[480,960,1440];return sizes[(sizes.indexOf(w)+(key==="right"?1:2))%3]});if(key==="return")void exportGif();return true}
      if(confirm){if(key==="escape")setConfirm(null);if(key==="return")confirm.action();return true}
      if(["1","2","3","4"].includes(key)){end();setTool(tools[Number(key)-1])}
      if(key==="["||key==="]"){end();setSize(value=>Math.max(1,Math.min(8,value+(key==="]"?1:-1))))}
      if(key==="c")setCycling(value=>!value);
      if(key==="v")reverse();
      if(key==="-")speed(1.25);
      if(key==="=")speed(.8);
      if(key==="e")setFg(TRANSPARENT);
      if(key==="x"){setFg(bg);setBg(fg)}
      if(key==="z"){end();painting.undo();redraw()}
      if(key==="y"){end();painting.redo();redraw()}
      if(key==="n")clear();
      if(key==="r")resize();
      if(key==="m")setPixelOutput(value=>!value);
      if(event.ctrl&&key==="o"){showOpen();return true}
      if(key==="h"){end();setHelpStatus("");setHelpOpen(true)}
      if(key==="g"){end();setExportOpen(true)}
      if(key==="s")void save();
      if(key==="q"||(event.ctrl&&key==="c"))quit();
      return true;
    });
    return()=>interceptKeys(null);
  },[busy,confirm,openDialog,openPath,helpOpen,helpTopic,exportOpen,exportWidth,tool,size,fg,bg,file,saved,revision]);
  const button=(label:string,action:()=>void,selected=false,id?:string)=><box id={id} height={1} flexShrink={0} paddingX={1} backgroundColor={selected?"#344eaa":"#c1c5d0"} onMouseDown={()=>{if(!busy&&!confirm&&!exportOpen&&!helpOpen&&!openDialog){end();action()}}}><text fg={selected?"#ffffff":"#182038"}>{label}</text></box>;
  const swatch=(index:number,id:string)=><box id={id} width={6} height={3} backgroundColor={index===TRANSPARENT?"#626778":palette[index]}>{index===TRANSPARENT&&[0,1,2].map(row=><text key={row} fg="#858b9b">{row%2?" ▀ ▀ ▀":"▀ ▀ ▀ "}</text>)}</box>;
  return <box width="100%" height="100%" backgroundColor="#a7acbc">
    <box height={1} flexShrink={0} backgroundColor="#344eaa" flexDirection="row" paddingX={1} justifyContent="space-between">
      <text fg="#ffffff"><b>termpaint</b> · pixel workshop</text><text fg="#ffe08a">{dirty?"* ":""}{painting.width} × {painting.height} · {kitty&&pixelOutput?"Kitty":"Half blocks"}</text>
    </box>
    <box height={1} flexShrink={0} flexDirection="row" gap={1} paddingX={1}>
      {button("Open",showOpen,false,"paint-open")}{button("Save",()=>void save(),false,"paint-save")}{button("New",clear)}{button("Resize",resize)}{button(kitty&&pixelOutput?"Kitty":"Blocks",()=>setPixelOutput(value=>!value))}{button("GIF",()=>setExportOpen(true))}{button("Undo",()=>{painting.undo();redraw()})}{button("Redo",()=>{painting.redo();redraw()})}
      <box flexGrow={1} minWidth={1}/>{button("Help",()=>{setHelpStatus("");setHelpOpen(true)},false,"paint-ai-help")}
    </box>
    <text height={1} flexShrink={0} fg="#34405a"> {file.split("/").pop()||file}</text>
    <box flexDirection="row" flexGrow={1} minHeight={0} gap={1} paddingX={1}>
      <box width={16} flexShrink={0} gap={0}>
        <text fg="#182038"><b>Tools</b></text>
        {labels.map((label,index)=>button(label,()=>setTool(tools[index]),tool===tools[index],"paint-tool-"+index))}
        <text fg="#182038">Brush radius: {size}</text>
        <box height={1} flexDirection="row" gap={1}>{button("−",()=>setSize(value=>Math.max(1,value-1)))}{button("+",()=>setSize(value=>Math.min(8,value+1)))}</box>
        <box flexDirection="row" gap={2} height={4} marginTop={1} marginBottom={1}>
          <box width={6}>{swatch(fg,"paint-foreground")}<text fg="#182038">  FG</text></box>
          <box width={6}>{swatch(bg,"paint-background")}<text fg="#182038">  BG</text></box>
        </box>
        {button("X Swap colors",()=>{setFg(bg);setBg(fg)})}
        <box id="paint-transparent" height={1} backgroundColor="#626778" onMouseDown={(e:any)=>{if(!busy&&!confirm&&!exportOpen&&!helpOpen&&!openDialog){if(backgroundClick(e))setBg(TRANSPARENT);else if(e.button===0)setFg(TRANSPARENT)}}}><text fg="#ffffff"> E Transparent</text></box>
        <text fg="#182038" marginTop={1}>Cycle {painting.cycle.start}–{painting.cycle.end}</text>
        {button(cycling?"C Pause cycle":"C Play cycle",()=>setCycling(value=>!value),cycling,"paint-cycle-play")}
        {button("Range = FG/BG",range)}
        {button(painting.cycle.direction===1?"V Forward →":"V Reverse ←",reverse)}
        <box height={1} flexDirection="row" gap={1}>{button("−",()=>speed(1.25))}{button("+",()=>speed(.8))}</box>
        <text fg="#182038">{painting.cycle.stepMs} ms / step</text>
        {button(painting.cycle.blend?"Smooth blend":"Stepped",()=>{painting.cycle={...painting.cycle,blend:!painting.cycle.blend};redraw()})}
        {button("Reset cycle",()=>{setCycling(false);elapsedRef.current=0;setElapsed(0)})}
      </box>
      <box padding={1} flexGrow={1} minWidth={0} minHeight={0} backgroundColor="#505668">
        {React.createElement("paintCanvas",{id:"paint-canvas",ref:canvas,painting,revision,palette:previewPalette,kitty:kitty&&pixelOutput,width:"100%",height:"100%",onMouseDown:start,onMouseDrag:(e:any)=>move(e,true),onMouseMove:(e:any)=>move(e),onMouseUp:end,onMouseOut:()=>{if(canvas.current){canvas.current.cursor=null;canvas.current.requestRender()}setPosition("")}})}
      </box>
    </box>
    <box height={4} flexShrink={0} paddingX={1} paddingTop={1}>
      {[0,1].map(row=><box key={row} height={1} flexDirection="row">
        {palette.slice(row*16,row*16+16).map((color,i)=>{const index=row*16+i;return <box id={"paint-color-"+index} key={color} width="6.25%" height={1} backgroundColor={displayPalette[index]}
          onMouseOver={()=>setHover(index)} onMouseOut={()=>setHover(null)}
          onMouseDown={(e:any)=>{if(!busy&&!confirm&&!exportOpen&&!helpOpen&&!openDialog){if(backgroundClick(e))setBg(index);else if(e.button===0)setFg(index)}}}>
          <text fg={index===0||index===2||index===6||index===13||index===19||index===20||index===21||index===22||index===29?"#ffffff":"#172038"}>{fg===index?"◆":bg===index?"◇":" "}</text>
        </box>})}
      </box>)}
      <text fg="#182038">{busy?"Working…":status} · {tool} · {position} · {fg===TRANSPARENT?"transparent":palette[fg]}</text>
    </box>
    <text height={1} flexShrink={0} fg="#ffffff" bg="#344eaa"> 1–4 tools · [/] size · Z/Y undo/redo · S save · R resize · M display · Q quit · Ctrl/right-drag BG</text>
    {openDialog&&<box position="absolute" left={2} top={3} width="90%" height={6} border borderColor="#ffffff" backgroundColor="#344eaa" paddingX={1}>
      <text fg="#ffffff">Open a .tpaint painting · Ctrl+O</text>
      <input id="paint-open-path" ref={pathInput} width="100%" height={1} value={openPath} onInput={setOpenPath} backgroundColor="#294650" focusedBackgroundColor="#294650" textColor="#ffffff"/>
      <box height={1} flexDirection="row" gap={3}><text fg="#ffe08a" onMouseDown={submitOpen}>[Enter Open]</text><text fg="#ffe08a" onMouseDown={()=>setOpenDialog(false)}>[Esc Cancel]</text></box>
    </box>}
    {helpOpen&&<box id="paint-ai-help-dialog" position="absolute" left={2} top={2} width="94%" height={17} border borderColor="#ffffff" backgroundColor="#344eaa" paddingX={1}>
      <text fg="#ffffff"><b>AI Help · bring your own assistant</b></text>
      <box height={1} flexDirection="row" gap={2}>{aiHelpTitles.map((title,i)=><text key={title} fg={i===helpTopic?"#ffe08a":"#ffffff"} onMouseDown={()=>{setHelpTopic(i);setHelpStatus("")}}>{i+1}. {title}</text>)}</box>
      <text fg="#ffffff">{helpTopic===0?"Teach your assistant the controls, file format, transparency, sprite workflow, and GIF export.":"Teach your assistant how to prompt imagegen, separate static and moving regions, assign palette phases, and inspect a complete color cycle."}</text>
      <text fg="#ffffff">Copy the guide below, paste it into your AI chat, and describe what you want to make. No AI service runs inside termpaint.</text>
      <text fg="#ffe08a">{helpTopic===0?"skills/termpaint/SKILL.md":"skills/termpaint-color-cycle/SKILL.md"}</text>
      <text fg="#ffffff">The copied guide includes the file format and operating instructions. The project skills can also be installed in your assistant's skill folder.</text>
      <box height={1} flexDirection="row" gap={3}><text id="paint-ai-copy" fg="#ffe08a" onMouseDown={copyGuide}>[C Copy guide]</text><text fg="#ffe08a" onMouseDown={()=>setHelpOpen(false)}>[Esc Close]</text></box>
      <text fg="#ffffff">{helpStatus||"1 / 2 selects a guide · C copies through your terminal clipboard"}</text>
    </box>}
    {exportOpen&&<box position="absolute" left={2} top={3} width="90%" height={9} border borderColor="#ffffff" backgroundColor="#344eaa" paddingX={1}>
      <text fg="#ffffff">Export animated GIF · one full cycle · loops forever</text>
      <box height={1} flexDirection="row" gap={2}>{[480,960,1440].map(w=><text key={w} fg={w===exportWidth?"#ffe08a":"#ffffff"} onMouseDown={()=>setExportWidth(w)}>{w===exportWidth?"●":"○"} {w} px</text>)}</box>
      <text fg="#ffffff">{exportWidth} × {Math.round(exportWidth*painting.height/painting.width)} · crisp pixels · transparency preserved</text>
      <text fg="#ffffff">{exportPath(exportWidth)}</text>
      <text fg="#ffffff">Left/Right chooses size · Enter exports · Esc cancels</text>
      <box height={1} flexDirection="row" gap={2}><text fg="#ffe08a" onMouseDown={()=>void exportGif()}>[Export]</text><text fg="#ffe08a" onMouseDown={()=>setExportOpen(false)}>[Cancel]</text></box>
    </box>}
    {confirm&&<box position="absolute" left={2} top={3} width="90%" height={5} border borderColor="#ffffff" backgroundColor="#344eaa" paddingX={1}>
      <text fg="#ffffff">{confirm.label}</text>
      <box height={1} flexDirection="row" gap={2}><text fg="#ffe08a" onMouseDown={()=>confirm.action()}>[Enter: yes]</text><text fg="#ffe08a" onMouseDown={()=>setConfirm(null)}>[Esc: cancel]</text></box>
    </box>}
  </box>;
}
mountDemo(App);
if(__host.headless)Object.assign(globalThis,{async __selfTest(){
  testPainting();testPaintingResize();testPaintingAlpha();testPaintingPalette();testCycle();
  const host=globalThis as any;
  const pause=async()=>{await new Promise(resolve=>setTimeout(resolve,90));host.__frame()};
  const feed=async(text:string)=>{host.__input(new TextEncoder().encode(text).buffer);await pause()};
  await pause();
  const canvas=[...Renderable.renderablesByNumber.values()].find(node=>node.id==="paint-canvas") as PaintCanvas;
  if(!canvas||!host.__snapshot().includes("termpaint"))throw new Error("Paint UI missing");
  const originalPixels=canvas.painting.pixels.slice();await feed("c");await pause();await feed("c");
  if(canvas.painting.pixels.some((n,i)=>n!==originalPixels[i]))throw new Error("Cycling changed pixels");
  const cycleCopy=new Painting();cycleCopy.load(canvas.painting.serialize());if(JSON.stringify(cycleCopy.cycle)!==JSON.stringify(canvas.painting.cycle))throw new Error("Cycle save failed");
  await feed("\x0f");if(!host.__snapshot().includes("Open a .tpaint"))throw new Error("Ctrl+O dialog missing");
  const pathField=[...Renderable.renderablesByNumber.values()].find(node=>node.id==="paint-open-path") as InputRenderable;
  const pathBefore=pathField.value;await feed("\x1b[200~test-paste\x1b[201~");
  if(pathField.value!==pathBefore+"test-paste")throw new Error("Path paste failed");await feed("\x1b");
  const helpBefore=canvas.painting.serialize();await feed("h");await feed("2");
  if(!host.__snapshot().includes("termpaint-color-cycle/SKILL.md"))throw new Error("AI help topic missing");
  await feed("1");if(!host.__snapshot().includes("skills/termpaint/SKILL.md"))throw new Error("AI help navigation failed");
  await feed("\x1b");if(canvas.painting.serialize()!==helpBefore)throw new Error("AI help modified artwork");
  if(!aiHelpPrompt(1).includes("spatial phase field")||!aiHelpPrompt(1).includes("0123456789abcdefghijklmnopqrstuv."))throw new Error("Copied guide missing content");
  const g=canvas.geometry(),x=g.x+2,y=g.y+2;
  await feed(`\x1b[<0;${x+1};${y+1}M\x1b[<32;${x+10};${y+1}M\x1b[<0;${x+10};${y+1}m`);
  if(!canvas.painting.pixels.includes(0))throw new Error("Mouse stroke did not paint");
  await feed("z");if(canvas.painting.pixels.some(n=>n!==1))throw new Error("UI undo failed");
  await feed("y");
  await feed("3");
  await feed(`\x1b[<0;${x+1};${y+1}M`);await pause();await feed(`\x1b[<0;${x+1};${y+1}m`);
  await feed("4");await feed(`\x1b[<0;${x+20};${y+3}M\x1b[<0;${x+20};${y+3}m`);
  await feed("s");
  for(let i=0;i<150&&!host.__snapshot().includes("Saved");i++)await pause();
  if(!host.__snapshot().includes("Saved"))throw new Error("Paint save failed");
  const result=await request({op:"load",path:(await request({op:"info"})).path});
  const loaded=new TextDecoder().decode(__host.takeBuffer(result.id)!);
  if(loaded!==canvas.painting.serialize())throw new Error("Saved painting differs from canvas");
  await feed("\x0f");await feed("\r");
  for(let i=0;i<60&&!host.__snapshot().includes("Loaded");i++)await pause();
  if(!host.__snapshot().includes("Loaded")||canvas.painting.serialize()!==loaded)throw new Error("Open saved painting failed");
  host.__resize(110,36);await pause();
  if(canvas.painting.serialize()!==loaded)throw new Error("Resize changed painting");
  await feed("r");await feed("\r");
  if(canvas.painting.width!==192||canvas.painting.height!==128)throw new Error("UI resize failed");
  await feed("z");if(canvas.painting.serialize()!==loaded)throw new Error("UI resize undo failed");
  keys.emit("graphics",true);await pause();if(canvas.kitty)throw new Error("Kitty became default");
  await feed("m");if(!canvas.kitty)throw new Error("Kitty opt-in failed");
  await feed("m");if(canvas.kitty)throw new Error("Block fallback toggle failed");
  const swatch=[...Renderable.renderablesByNumber.values()].find(node=>node.id==="paint-color-8")!;
  await feed(`\x1b[<0;${swatch.x+1};${swatch.y+1}M\x1b[<0;${swatch.x+1};${swatch.y+1}m`);
  if(!host.__snapshot().includes(palette[8]))throw new Error("Palette click did not select color");
  await feed("1");await feed("e");
  const alphaPoint=canvas.geometry();
  await feed(`\x1b[<0;${alphaPoint.x+2};${alphaPoint.y+2}M\x1b[<0;${alphaPoint.x+2};${alphaPoint.y+2}m`);
  if(!canvas.painting.pixels.includes(TRANSPARENT))throw new Error("Transparent brush failed");
  await feed("m");if(!canvas.kitty)throw new Error("Alpha Kitty render missing");
  await feed(`\x1b[<16;${swatch.x+1};${swatch.y+1}M\x1b[<16;${swatch.x+1};${swatch.y+1}m`);
  const g2=canvas.geometry(),startPoint=canvas.point(g2.x+1,g2.y+1)!,endPoint=canvas.point(g2.x+4,g2.y+1)!;
  await feed(`\x1b[<16;${g2.x+2};${g2.y+2}M\x1b[<48;${g2.x+5};${g2.y+2}M\x1b[<16;${g2.x+5};${g2.y+2}m`);
  for(let px=startPoint.x;px<=endPoint.x;px++)if(canvas.painting.pixels[startPoint.y*canvas.painting.width+px]!==8)throw new Error("Ctrl-drag did not use selected background");
  const transparent=[...Renderable.renderablesByNumber.values()].find(node=>node.id==="paint-transparent")!;
  await feed(`\x1b[<16;${transparent.x+1};${transparent.y+1}M\x1b[<16;${transparent.x+1};${transparent.y+1}m`);
  await feed(`\x1b[<2;${g2.x+2};${g2.y+2}M\x1b[<2;${g2.x+2};${g2.y+2}m`);
  if(canvas.painting.pixels[startPoint.y*canvas.painting.width+startPoint.x]!==TRANSPARENT)throw new Error("Ctrl-select transparent/right-click paint failed");
  await feed("g");if(!host.__snapshot().includes("960 × 640"))throw new Error("GIF dimensions missing");
  await feed("\x1b[C");if(!host.__snapshot().includes("1440 × 960"))throw new Error("GIF size navigation failed");await feed("\x1b");
  const gifSource=canvas.painting.serialize();await request({op:"begin"});for(let i=0;i<gifSource.length;i+=1024)await request({op:"append",text:gifSource.slice(i,i+1024)});
  const testPath=(await request({op:"info"})).path;
  try{await request({op:"gif",path:testPath,width:480});throw new Error("GIF replaced file without confirmation")}catch(e){if((e as Error).message!=="FileExists")throw e}
  await request({op:"gif",path:testPath,width:480,overwrite:true});
  if(canvas.painting.serialize()!==gifSource)throw new Error("Export mutated painting");



}});
