import "./lab-cells";
import React,{useEffect,useRef,useState} from "../vendor/js/node_modules/react";
import {Renderable} from "../vendor/opentui/packages/core/src/Renderable";
import {NativeImage} from "../vendor/opentui/packages/core/src/image";
import {mountDemo,keys,graphicsState} from "./platform/demo";
const WIDTH=240,HEIGHT=160;
type Scene={shape:number,angle:number,tilt:number,zoom:number,wire:boolean,palette:number,playing:boolean,fps:number,tone:number,brightness:number,contrast:number,dot_scale:number,fractal_zoom:number,center_x:number,center_y:number};
type Frame={image:NativeImage,pixels:Uint8Array,ms:number,index:number,dropped:number,serial:number};
const ownedImages=new Map<NativeImage,number>();
function releaseBefore<T extends {dispose():void}>(images:Map<T,number>,committed:number){
  // A delayed effect must never release a newer frame waiting for its commit.
  for(const [image,serial] of images)if(serial<committed){image.dispose();images.delete(image)}
}
const frameListeners=new Set<(frame:Frame)=>void>();
let framesReceived=0;
const deliveries:number[]=[];
Object.assign(globalThis,{__message(message:string){
  const event=JSON.parse(message);
  if(event.type!=="frame-ready")return;
  const bytes=__host.takeBuffer(event.id);
  if(!bytes)return; // The worker may already have replaced a stale frame.
  const image=NativeImage.fromRgba(new Uint8Array(bytes),event.width,event.height);
  framesReceived++;
  deliveries.push(Date.now());
  if(deliveries.length>240)deliveries.splice(0,deliveries.length-240);
  if(frameListeners.size===0){image.dispose();return;}
  ownedImages.set(image,framesReceived);
  for(const listener of frameListeners)listener({image,pixels:new Uint8Array(bytes),ms:event.ms,index:event.id,dropped:event.dropped,serial:framesReceived});
}});
declare const __host:{headless:boolean,postMessage(text:string):boolean,takeBuffer(id:number):ArrayBuffer|null};
const names=["Torus","Orb","Sheet","4D hypercube","Mandelbrot"];
const tones=["Color","Grayscale","Screen Bayer","Surface fractal"];
function App(){
  const scene=useRef<Scene>({shape:3,angle:0,tilt:.7,zoom:.82,wire:false,palette:0,playing:true,fps:10,tone:0,brightness:0,contrast:1,dot_scale:4,fractal_zoom:1,center_x:-.65,center_y:0});
  const playing=useRef(true),drag=useRef<{x:number,y:number}|null>(null);
  const [frame,setFrame]=useState<Frame|null>(null);
  const [fps,setFps]=useState(0);
  const [output,setOutput]=useState(0);
  const [kitty,setKitty]=useState(graphicsState.confirmed);
  const [,refresh]=useState(0);
  const draw=()=>{
    scene.current.playing=playing.current&&!drag.current;
    if(!__host.postMessage(JSON.stringify(scene.current)))throw new Error("Native renderer rejected scene");
    refresh(n=>n+1);
  };
  useEffect(()=>{
    // React can coalesce several frames before a commit. Release skipped ones too.
    releaseBefore(ownedImages,frame?.serial??0);
  },[frame?.image]);
  useEffect(()=>()=>{for(const image of ownedImages.keys())image.dispose();ownedImages.clear()},[]);
  useEffect(()=>{
    const timer=setInterval(()=>{
      const cutoff=Date.now()-1000;
      while(deliveries.length&&deliveries[0]<cutoff)deliveries.shift();
      setFps(deliveries.length);
    },500);
    return()=>clearInterval(timer);
  },[]);
  useEffect(()=>{
    const key=(name:string)=>{
      if(["1","2","3","4","5"].includes(name))scene.current.shape=Number(name)-1;
      if(name==="-"||name==="="){
        const rates=[1,5,10,15,20,30,45,60,90,120];
        const index=rates.indexOf(scene.current.fps);
        scene.current.fps=rates[Math.max(0,Math.min(rates.length-1,index+(name==="="?1:-1)))];
      }
      if(name==="m")setOutput(value=>(value+1)%3);
      if(name==="d")scene.current.tone=(scene.current.tone+1)%4;
      if(name==="b")scene.current.brightness=Math.min(1,scene.current.brightness+.1);
      if(name==="n")scene.current.brightness=Math.max(-1,scene.current.brightness-.1);
      if(name==="k")scene.current.contrast=Math.min(4,scene.current.contrast+.25);
      if(name==="j")scene.current.contrast=Math.max(.25,scene.current.contrast-.25);
      if(name==="o")scene.current.dot_scale=Math.min(5,scene.current.dot_scale+.25);
      if(name==="i")scene.current.dot_scale=Math.max(0,scene.current.dot_scale-.25);
      if(name==="r"){Object.assign(scene.current,{zoom:.82,fractal_zoom:1,center_x:-.65,center_y:0,brightness:0,contrast:1,dot_scale:4,angle:0,tilt:.7})}
      if(name==="t"){scene.current.shape=4;scene.current.center_x=-.743643887037151;scene.current.center_y=.13182590420533;scene.current.fractal_zoom=250}
      if(name==="w")scene.current.wire=!scene.current.wire;
      if(name==="c")scene.current.palette=(scene.current.palette+1)%3;
      if(name==="p"||name==="space")playing.current=!playing.current;
      if(scene.current.shape===4){
        const step=.2/scene.current.fractal_zoom;
        if(name==="left")scene.current.center_x-=step;if(name==="right")scene.current.center_x+=step;
        if(name==="up")scene.current.center_y-=step;if(name==="down")scene.current.center_y+=step;
        scene.current.center_x=Math.max(-4,Math.min(4,scene.current.center_x));scene.current.center_y=Math.max(-4,Math.min(4,scene.current.center_y));
      }else{
        if(name==="left")scene.current.angle-=.15;if(name==="right")scene.current.angle+=.15;
        if(name==="up")scene.current.tilt+=.15;if(name==="down")scene.current.tilt-=.15;
      }
      draw();
    };
    const graphics=(confirmed:boolean)=>setKitty(confirmed);
    keys.on("key",key);keys.on("graphics",graphics);
    frameListeners.add(setFrame);draw();
    return()=>{frameListeners.delete(setFrame);keys.off("key",key);keys.off("graphics",graphics)};
  },[]);
  return <box width="100%" height="100%" padding={1} backgroundColor="#101820">
    <box border borderStyle="rounded" borderColor="#63c7b2" title=" 05 / Graphics lab " paddingX={1} width="100%" height="100%" gap={1}>
      <text height={1} flexShrink={0} fg="#f6f0dd"><b>Light, geometry, and terminal pixels</b></text>
      <box flexDirection="row" height={1} flexShrink={0} gap={1}>
        {names.map((name,i)=><box key={name} paddingX={1} backgroundColor={scene.current.shape===i?"#294650":"#192932"} onMouseDown={()=>{scene.current.shape=i;draw()}}><text fg="#63c7b2">{i+1} {name}</text></box>)}
      </box>
      <box id="lab-canvas" flexGrow={1} minHeight={0} width="100%" overflow="hidden"
        onMouseDown={(e:any)=>{if(e.button===0){drag.current={x:e.x,y:e.y};draw()}}}
        onMouseDrag={(e:any)=>{
          if(!drag.current)return;
          if(scene.current.shape===4){
            const node=e.currentTarget;
            const scale=3.2/scene.current.fractal_zoom/Math.max(1,node?.width??100);
            scene.current.center_x=Math.max(-4,Math.min(4,scene.current.center_x-(e.x-drag.current.x)*scale));
            scene.current.center_y=Math.max(-4,Math.min(4,scene.current.center_y-(e.y-drag.current.y)*scale*2));
          }else{scene.current.angle+=(e.x-drag.current.x)*.06;scene.current.tilt+=(e.y-drag.current.y)*.1}
          drag.current={x:e.x,y:e.y};draw();
        }}
        onMouseUp={()=>{drag.current=null;draw()}}
        onMouseScroll={(e:any)=>{if(scene.current.shape===4)scene.current.fractal_zoom=Math.max(.5,Math.min(1e10,scene.current.fractal_zoom*(e.scroll.direction==="up"?1.25:.8)));
          else scene.current.zoom=Math.max(.3,Math.min(1.4,scene.current.zoom+(e.scroll.direction==="up"?.07:-.07)));draw()}}>
        {frame?(output===0?<image source={frame.image} width="100%" height="100%" protocol={kitty?"kitty":"blocks"} onError={(error:any)=>{throw error}}/>:React.createElement("labCells",{pixels:frame.pixels,mode:output===1?"half":"braille",width:"100%",height:"100%"})):<text fg="#718b99">Waiting for native frame…</text>}
      </box>
      <text height={1} flexShrink={0} fg="#c2ced5">{names[scene.current.shape]} · {scene.current.wire?"wireframe":"shaded"} · {playing.current?"playing":"paused"} · {fps} FPS delivered · -/= target {scene.current.fps} · {frame?.ms??0} ms CPU · drop {frame?.dropped??0}</text>
      <text height={1} flexShrink={0} fg="#718b99">Drag rotate/pan · scroll zoom · W wire · C palette · P pause · R reset · T fractal target · Q exit</text>
      <text height={1} flexShrink={0} fg="#c2ced5">D {tones[scene.current.tone]} · B/N brightness {scene.current.brightness.toFixed(1)} · K/J contrast {scene.current.contrast.toFixed(2)} · O/I dots {scene.current.dot_scale.toFixed(2)}</text>
      <text height={1} flexShrink={0} fg="#526b78">M {output===1?"Half blocks":output===2?"Braille":kitty?"Kitty pixels":"Block fallback"} · {WIDTH} × {HEIGHT} · {scene.current.shape===4?scene.current.fractal_zoom.toFixed(1)+"× zoom":"Zig CPU worker → React → terminal"}</text>
    </box>
  </box>;
}
mountDemo(App);
if(__host.headless)Object.assign(globalThis,{async __selfTest(){
  const released:number[]=[];
  const mock=new Map([1,2,3].map(serial=>[{dispose(){released.push(serial)}},serial] as const));
  releaseBefore(mock,2);
  if(released.join(",")!=="1"||mock.size!==2)throw new Error("Pending frames must survive older commits");
  releaseBefore(mock,3);
  if(released.join(",")!=="1,2"||mock.size!==1)throw new Error("Superseded frames must be released");
  const host=globalThis as any;
  const wait=()=>new Promise(resolve=>setTimeout(resolve,30));
  for(const key of ["p","2","3","1","w","c","left"]){host.__input(new TextEncoder().encode(key).buffer);await wait()}
  const snapshot=host.__snapshot();
  if(!snapshot.includes("wireframe")||!snapshot.includes("paused"))throw new Error("Lab controls failed");
  const deadline=Date.now()+3000;
  while(framesReceived<2&&Date.now()<deadline)await wait();
  if(framesReceived<2)throw new Error("Native worker must deliver frames through messages");
  const canvas=[...Renderable.renderablesByNumber.values()].find(node=>node.id==="lab-canvas")!;
  host.__input(new TextEncoder().encode("p").buffer);
  const before=framesReceived;
  for(let i=0;i<60;i++){
    const wheel=`\x1b[<${i%2?65:64};${canvas.x+3};${canvas.y+3}M`;
    host.__input(new TextEncoder().encode(wheel).buffer);
    await new Promise(resolve=>setTimeout(resolve,4));
  }
  await wait();
  if(framesReceived<=before)throw new Error("Zoom must keep receiving native frames");
  for(const [key,label] of [["=","target 15"],["-","target 10"],["4","4D hypercube"],["5","Mandelbrot"],["t","250.0× zoom"],["d","Grayscale"],["d","Screen Bayer"],["d","Surface fractal"],["m","Half blocks"],["m","Braille"],["m","Block fallback"]]){
    host.__input(new TextEncoder().encode(key).buffer);await wait();
    if(!host.__snapshot().includes(label))throw new Error("Missing lab control state: "+label);
    if(label==="Half blocks"&&!host.__snapshot().includes("▀"))throw new Error("Half-block canvas must draw cells");
    if(label==="Braille"&&!/[\u2801-\u28ff]/.test(host.__snapshot()))throw new Error("Braille canvas must draw dots");
  }
  if(__host.takeBuffer(0)!==null)throw new Error("Unknown frame IDs must not expose pixels");
}});
