import {Cycle,defaultCycle,validCycle} from "./paint-cycle";
export const palette=["#172038","#f4f4e8","#465074","#8585a1","#bfc7cf","#ffffff","#703040","#b13e53","#ef7d57","#ffcd75","#a7f070","#38b764","#257179","#29366f","#3b5dc9","#41a6f6","#73eff7","#f4b5d5","#de5b9e","#8f3f95","#5b2b82","#402751","#663931","#8f563b","#bf8c60","#dfb580","#e7d5b3","#a6b7a5","#597d75","#334f5a","#ff4038","#ffe600"];
export type Tool="pencil"|"brush"|"spray"|"fill";
export const TRANSPARENT=32;
const pixelAlphabet="0123456789abcdefghijklmnopqrstuv.";
function validSize(w:number,h:number){return Number.isInteger(w)&&Number.isInteger(h)&&w>=16&&h>=16&&w<=256&&h<=192}
export class Painting {
  width=96;height=64;
  palette=palette.slice();
  cycle:Cycle=defaultCycle();
  pixels=new Uint8Array(this.width*this.height).fill(1);
  undoStack:{width:number,height:number,pixels:Uint8Array}[]=[];redoStack:{width:number,height:number,pixels:Uint8Array}[]=[];
  snapshot(){return {width:this.width,height:this.height,pixels:this.pixels.slice()}}
  restore(value:{width:number,height:number,pixels:Uint8Array}){this.width=value.width;this.height=value.height;this.pixels=value.pixels}
  checkpoint(){this.undoStack.push(this.snapshot());if(this.undoStack.length>32)this.undoStack.shift();this.redoStack=[]}
  undo(){const old=this.undoStack.pop();if(old){this.redoStack.push(this.snapshot());this.restore(old)}}
  redo(){const next=this.redoStack.pop();if(next){this.undoStack.push(this.snapshot());this.restore(next)}}
  dot(x:number,y:number,color:number){if(x>=0&&y>=0&&x<this.width&&y<this.height)this.pixels[y*this.width+x]=color}
  stamp(x:number,y:number,color:number,radius:number,tool:Tool,random= Math.random){
    if(tool==="spray"){
      for(let i=0;i<12;i++){const angle=random()*Math.PI*2,r=Math.sqrt(random())*(radius+1);this.dot(Math.round(x+Math.cos(angle)*r),Math.round(y+Math.sin(angle)*r),color)}
      return;
    }
    const r=tool==="pencil"?0:radius;
    for(let dy=-r;dy<=r;dy++)for(let dx=-r;dx<=r;dx++)if(dx*dx+dy*dy<=r*r)this.dot(x+dx,y+dy,color);
  }
  line(x:number,y:number,toX:number,toY:number,color:number,radius:number,tool:Tool){
    const dx=Math.abs(toX-x),dy=-Math.abs(toY-y),sx=x<toX?1:-1,sy=y<toY?1:-1;let error=dx+dy;
    while(true){this.stamp(x,y,color,radius,tool);if(x===toX&&y===toY)break;const e=2*error;if(e>=dy){error+=dy;x+=sx}if(e<=dx){error+=dx;y+=sy}}
  }
  fill(x:number,y:number,color:number){
    const start=y*this.width+x,old=this.pixels[start];if(old===color)return;
    const queue=[start];this.pixels[start]=color;
    while(queue.length){const at=queue.pop()!,cx=at%this.width,cy=Math.floor(at/this.width);
      for(const next of [cx?at-1:-1,cx<this.width-1?at+1:-1,cy?at-this.width:-1,cy<this.height-1?at+this.width:-1]){
        if(next>=0&&this.pixels[next]===old){this.pixels[next]=color;queue.push(next)}
      }
    }
  }
  resize(width:number,height:number){
    if(!validSize(width,height))throw new Error("Invalid canvas size");
    const pixels=new Uint8Array(width*height);
    for(let y=0;y<height;y++)for(let x=0;x<width;x++)pixels[y*width+x]=this.pixels[Math.floor(y*this.height/height)*this.width+Math.floor(x*this.width/width)];
    this.checkpoint();this.restore({width,height,pixels});
  }
  rgba(displayPalette=this.palette){
    const bytes=new Uint8Array(this.pixels.length*4);
    for(let i=0;i<this.pixels.length;i++){
      if(this.pixels[i]===TRANSPARENT)continue;
      const hex=displayPalette[this.pixels[i]];
      for(let c=0;c<3;c++)bytes[i*4+c]=parseInt(hex.slice(1+c*2,3+c*2),16);
      bytes[i*4+3]=255;
    }
    return bytes;
  }
  serialize(){return JSON.stringify({format:"termpaint",version:3,palette:this.palette,cycle:this.cycle,width:this.width,height:this.height,pixels:Array.from(this.pixels,n=>pixelAlphabet[n]).join("")})}
  load(text:string){
    const data=JSON.parse(text);
    if(data.format!=="termpaint"||!validSize(data.width,data.height))throw new Error("Invalid termpaint file");
    const loadedPalette=data.palette??palette;
    if(!Array.isArray(loadedPalette)||loadedPalette.length!==32||loadedPalette.some((c:any)=>typeof c!=="string"||!/^#[0-9a-fA-F]{6}$/.test(c)))throw new Error("Invalid palette");
    const cycle=data.cycle??defaultCycle();if(!validCycle(cycle))throw new Error("Invalid color cycle");
    let pixels:any;
    if(data.version===1&&Array.isArray(data.pixels))pixels=data.pixels;
    else if((data.version===2||data.version===3)&&typeof data.pixels==="string")pixels=Array.from(data.pixels,(n:string)=>pixelAlphabet.indexOf(n));
    if(!pixels||pixels.length!==data.width*data.height||pixels.some((n:any)=>!Number.isInteger(n)||n<0||n>=(data.version===3?33:32)))throw new Error("Invalid termpaint file");
    this.checkpoint();this.palette=loadedPalette.slice();this.cycle={...cycle};this.restore({width:data.width,height:data.height,pixels:Uint8Array.from(pixels)});
  }
}
export function testPainting(){
  const p=new Painting();p.checkpoint();p.line(2,3,20,3,7,0,"pencil");
  for(let x=2;x<=20;x++)if(p.pixels[3*p.width+x]!==7)throw new Error("Pencil stroke gaps");
  p.undo();if(p.pixels.some(n=>n!==1))throw new Error("Undo failed");p.redo();
  p.fill(0,0,4);if(p.pixels[3*p.width+2]!==7||p.pixels[0]!==4)throw new Error("Fill crossed color boundary");
  p.stamp(40,30,9,2,"brush");if(p.pixels[30*p.width+42]!==9)throw new Error("Brush radius failed");
  p.stamp(60,40,12,3,"spray",()=>.5);if(!p.pixels.includes(12))throw new Error("Spray failed");
  const before=p.serialize();p.load(before);if(p.serialize()!==before)throw new Error("Paint file round trip failed");
  try{p.load('{"format":"bad"}');throw new Error("Invalid file accepted")}catch(e){if((e as Error).message==="Invalid file accepted")throw e}
  if(p.serialize()!==before)throw new Error("Invalid file damaged painting");
}

export function testPaintingResize(){
  const p=new Painting();p.dot(20,30,30);const before=p.serialize();
  p.resize(192,128);if(p.pixels[60*192+40]!==30||p.pixels[61*192+41]!==30)throw new Error("Resize lost nearest-neighbor pixels");
  p.undo();if(p.serialize()!==before)throw new Error("Resize undo failed");p.redo();
  const q=new Painting();q.load(p.serialize());if(q.serialize()!==p.serialize())throw new Error("Resized round trip failed");
  p.resize(256,192);if(p.serialize().length>=65536)throw new Error("Painting exceeds file worker limit");
  const good=p.serialize();for(const pixels of ["!".repeat(256*192),"0"]){try{p.load(JSON.stringify({format:"termpaint",version:2,width:256,height:192,pixels}))}catch{}}
  if(p.serialize()!==good)throw new Error("Invalid pixels damaged painting");
  q.load(JSON.stringify({format:"termpaint",version:1,width:96,height:64,pixels:Array(6144).fill(9)}));
  if(q.width!==96||q.pixels.some(n=>n!==9))throw new Error("Legacy painting load failed");
}

export function testPaintingAlpha(){
  const p=new Painting();p.checkpoint();p.fill(0,0,TRANSPARENT);p.dot(5,5,30);
  const q=new Painting();q.load(p.serialize());
  if(q.pixels[0]!==TRANSPARENT||q.rgba()[3]!==0||q.rgba()[(5*96+5)*4+3]!==255)throw new Error("Alpha round trip failed");
  p.undo();if(p.pixels[0]!==1)throw new Error("Alpha undo failed");p.redo();
  p.resize(192,128);if(p.pixels[0]!==TRANSPARENT)throw new Error("Resize lost alpha");
  const before=q.serialize();try{q.load(before.replace('"version":3','"version":2'))}catch{}
  if(q.serialize()!==before)throw new Error("Legacy format accepted alpha");
}

export function testPaintingPalette(){
 const p=new Painting();p.palette[1]="#123456";const q=new Painting();q.load(p.serialize());
 if(q.rgba()[0]!==18||q.palette[1]!=="#123456")throw new Error("Custom palette round trip failed");
 const before=q.serialize();try{q.load(before.replace("#123456","invalid"))}catch{}
 if(q.serialize()!==before)throw new Error("Invalid palette damaged painting");
}
