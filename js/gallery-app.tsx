import React, { useState, useRef } from "../vendor/js/node_modules/react";
import { SyntaxStyle } from "../vendor/opentui/packages/core/src/syntax-style";

export const pages=["Text & layout","Input & textarea","Select & tabs","Scroll & sliders","ASCII fonts","Code & lines","Diff","Markdown & tables"];
const ink="#d5e2e8",muted="#8299a6",accent="#63c7b2";
const code='const dragon = { name: "Ember", wings: 2 };\n\nfunction fly(height) {\n  return `${dragon.name} flies ${height}m`;\n}\n\nconsole.log(fly(12));';
const patch='--- a/dragon.js\n+++ b/dragon.js\n@@ -1,4 +1,5 @@\n const dragon = {\n-  wings: 0,\n+  wings: 2,\n+  mood: "curious",\n   name: "Ember"\n };\n';
let syntax:SyntaxStyle;
export function disposeGallery(){syntax?.destroy()}
function style(){return syntax??=SyntaxStyle.fromStyles({default:{fg:ink},"markup.heading":{fg:accent,bold:true},"markup.strong":{bold:true},"markup.italic":{italic:true},"markup.link":{fg:"#9cbde8",underline:true},"markup.raw":{fg:"#e9af70"}})}
function Hint({children}:any){return <text fg={muted}>{children}</text>}
function TextDemo(){return <box gap={1}>
  <text fg={ink}>Plain text, <b>bold</b>, <i>italic</i>, <u>underline</u>.<br/>A line break and <span fg={accent}>a colored span</span>.</text>
  <text><a href="https://opentui.com">OpenTUI hyperlink</a></text>
  <text fg={ink}>Unicode: café · é · 日本語 · 👩‍💻</text>
  <box flexDirection="row" gap={1} height={5}>
    <box border borderStyle="rounded" borderColor={accent} flexGrow={1} padding={1}><text fg={accent}>Flex: 1</text></box>
    <box border borderStyle="double" borderColor="#e9af70" flexGrow={2} padding={1}><text fg="#e9af70">Flex: 2</text></box>
  </box>
  <Hint>Boxes provide borders, padding, alignment, clipping, and flex layout.</Hint>
</box>}
function InputDemo(){
 const [value,setValue]=useState("");const [submitted,setSubmitted]=useState("nothing yet");const [length,setLength]=useState(0);const editor=useRef<any>(null);
 return <box gap={1}>
  <Hint>Click a field or press Tab. Type, paste, select with Shift+arrows.</Hint>
  <input id="gallery-input" height={1} width="100%" placeholder="Name your dragon…" backgroundColor="#20353f" focusedBackgroundColor="#294650" textColor={ink} onInput={setValue} onSubmit={()=>setSubmitted(value)} />
  <text fg={accent}>Name: {value||"(empty)"}</text>
  <text fg={muted}>Submitted: {submitted}</text>
  <textarea id="gallery-textarea" ref={editor} height={6} width="100%" initialValue="Field notes:\n" backgroundColor="#20353f" focusedBackgroundColor="#294650" textColor={ink} onContentChange={()=>setLength(editor.current?.plainText.length??0)}/>
  <text fg={muted}>Notes: {length} characters · Enter adds a line · Ctrl+Z undo</text>
 </box>
}
function SelectDemo(){
 const [choice,setChoice]=useState("none");const [tab,setTab]=useState("Habitat");
 const options=[{name:"Ember",description:"A curious forest dragon"},{name:"Nimbus",description:"A sleepy cloud dragon"},{name:"Moss",description:"A tiny garden dragon"}];
 return <box gap={1}>
  <Hint>Tab focuses each widget. Arrow keys move; Enter chooses.</Hint>
  <select id="gallery-select" height={7} width="100%" options={options} selectedBackgroundColor="#294650" selectedTextColor={accent} textColor={ink} onSelect={(_i:number,o:any)=>setChoice(o.name)}/>
  <text fg={accent}>Chosen: {choice}</text>
  <tab-select id="gallery-tabs" height={3} width="100%" tabWidth={15} options={[{name:"Habitat",description:"Forest"},{name:"Food",description:"Berries"},{name:"Skills",description:"Flying"}]} onChange={(_i:number,o:any)=>setTab(o.name)}/>
  <text fg={accent}>Active tab: {tab}</text>
 </box>
}
function ScrollDemo(){const [value,setValue]=useState(25);return <box gap={1}>
 <Hint>Scroll with two fingers, drag the scrollbar, or focus and use arrows.</Hint>
 <scrollbox id="gallery-scroll" onMouseScroll={(e:any)=>e.stopPropagation()} height={9} width="100%" border borderColor={accent} scrollY contentOptions={{gap:0}}>
  {Array.from({length:40},(_,i)=><text key={i} fg={i%2?ink:accent}>Field record {String(i+1).padStart(2,"0")} · dragon sighting</text>)}
 </scrollbox>
 <text fg={ink}>Flight altitude: {Math.round(value)} m</text>
 <slider id="gallery-slider" orientation="horizontal" height={1} width="100%" min={0} max={100} value={value} onChange={setValue} foregroundColor={accent}/>
 <Hint>The scrollbox above contains native ScrollBar and Slider widgets.</Hint>
 </box>}
function FontDemo(){return <box gap={1}>
 <ascii-font text="DRAGON" font="tiny" color={accent}/>
 <ascii-font text="ZIG" font="block" color="#e9af70"/>
 <ascii-font text="JS" font="shade" color="#a59de0"/>
 <Hint>ASCII fonts render into an OpenTUI framebuffer.</Hint>
 </box>}
function CodeDemo(){return <box gap={1}>
 <Hint>Code with a line-number gutter. Plain text; syntax parsing is not enabled.</Hint>
 <line-number id="gallery-lines" height={10} width="100%" fg={muted}>
  <code id="gallery-code" content={code} syntaxStyle={style()} fg={ink} width="100%" height={10}/>
 </line-number>
 </box>}
function DiffDemo(){const [split,setSplit]=useState(false);return <box gap={1}>
 <box id="gallery-diff-toggle" height={1} onMouseDown={()=>setSplit(v=>!v)}><text fg={accent}>[ Click to switch: {split?"split":"unified"} ]</text></box>
 <diff id="gallery-diff" diff={patch} syntaxStyle={style()} view={split?"split":"unified"} height={12} width="100%"/>
 </box>}
function MarkdownDemo(){return <box gap={1}>
 <markdown id="gallery-markdown" width="100%" syntaxStyle={style()} content={'# Dragon field guide\n\n**Ember** has *two wings* and likes `berries`.\n\n- Forest habitat\n- Friendly disposition\n\n> Approach with snacks.\n'}/>
 <table id="gallery-table" width="100%" border borderColor={accent} fg={ink} content={[["Dragon","Habitat","Wings"],["Ember","Forest","2"],["Nimbus","Clouds","2"],["Moss","Garden","0"]]}/>
 </box>}
const demos=[TextDemo,InputDemo,SelectDemo,ScrollDemo,FontDemo,CodeDemo,DiffDemo,MarkdownDemo];
export function Gallery({page,changePage}:{page:number,changePage:(page:number)=>void}){
 const Demo=demos[page];
 return <box width="100%" height="100%" backgroundColor="#101820" padding={1}>
  <box flexDirection="row" width="100%" height={2}><text fg={accent}><b>QuickTUI / Widget gallery</b></text></box>
  <box flexDirection="row" flexGrow={1} gap={1}>
   <box width={24} border borderStyle="rounded" borderColor="#36535f" paddingX={1}>
    {pages.map((name,i)=><box id={`gallery-nav-${i}`} key={name} height={2} backgroundColor={page===i?"#294650":"#101820"} onMouseDown={()=>changePage(i)}><text fg={page===i?accent:muted}>{i+1}. {name}</text></box>)}
   </box>
   <box border borderStyle="rounded" borderColor={accent} title={` ${pages[page]} `} padding={1} flexGrow={1} minWidth={0}>
    <scrollbox key={page} flexGrow={1} width="100%" contentOptions={{paddingRight:1}}><Demo/></scrollbox>
   </box>
  </box>
  <text fg={muted}>Click page · F1/F2 previous/next · Tab focus · Esc exit</text>
 </box>
}
