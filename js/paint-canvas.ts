import {NativeImage} from "../vendor/opentui/packages/core/src/image";
import {Renderable} from "../vendor/opentui/packages/core/src/Renderable";
import {RGBA} from "../vendor/opentui/packages/core/src/lib/RGBA";
import {extend} from "./platform/catalogue";
import {palette,Painting,TRANSPARENT} from "./paint-model";
const checker=[RGBA.fromHex("#626778"),RGBA.fromHex("#858b9b")];
const checkerRGB=[[98,103,120],[133,139,155]];
const check=(x:number,y:number)=>(Math.floor(x/4)+Math.floor(y/4))%2;
const colors=palette.map(color=>RGBA.fromHex(color)),surround=RGBA.fromHex("#505668");
export class PaintCanvas extends Renderable {
  private displayPalette=palette;private paletteSerial=0;
  set palette(value:string[]){if(value.join()!==this.displayPalette.join()){this.displayPalette=value;this.paletteSerial++;this.requestRender()}}
  private image:NativeImage|null=null;private imageKey="";private version=0;private useKitty=false;
  set kitty(value:boolean){this.useKitty=value;this.requestRender()}
  get kitty(){return this.useKitty}
  painting:Painting;cursor:{x:number,y:number}|null=null;
  constructor(ctx:any,options:any){super(ctx,options);this.painting=options.painting}
  set revision(value:number){this.version=value;this.requestRender()}
  geometry(){
    const scale=Math.max(.01,Math.min(this.width/this.painting.width,this.height*2/this.painting.height));
    const w=Math.max(1,Math.floor(this.painting.width*scale)),h=Math.max(1,Math.floor(this.painting.height*scale/2));
    return {x:this.x+Math.floor((this.width-w)/2),y:this.y+Math.floor((this.height-h)/2),w,h};
  }
  point(x:number,y:number){
    const g=this.geometry();
    if(x<g.x||y<g.y||x>=g.x+g.w||y>=g.y+g.h)return null;
    return {x:Math.min(this.painting.width-1,Math.floor((x-g.x)*this.painting.width/g.w)),y:Math.min(this.painting.height-1,Math.floor((y-g.y)*this.painting.height/g.h))};
  }
  protected renderSelf(buffer:any){
    const g=this.geometry(),p=this.painting,colors=this.displayPalette.map(color=>RGBA.fromHex(color));
    if(this.cursor&&(this.cursor.x>=p.width||this.cursor.y>=p.height))this.cursor=null;
    for(let y=0;y<this.height;y++)buffer.drawText(" ".repeat(this.width),this.x,this.y,surround,surround);
    if(this.useKitty){
      const key=`${this.paletteSerial}:${this.version}:${p.width}:${p.height}:${this.cursor?.x}:${this.cursor?.y}`;
      if(!this.image||key!==this.imageKey){
        const bytes=p.rgba(this.displayPalette);
        for(let i=0;i<p.pixels.length;i++){
          if(p.pixels[i]===TRANSPARENT){const rgb=checkerRGB[check(i%p.width,Math.floor(i/p.width))];bytes.set(rgb,i*4);bytes[i*4+3]=255}
        }
        if(this.cursor){
          for(const [dx,dy] of [[-1,0],[1,0],[0,-1],[0,1]]){
            const x=this.cursor.x+dx,y=this.cursor.y+dy;
            if(x>=0&&y>=0&&x<p.width&&y<p.height){const i=(y*p.width+x)*4;for(let c=0;c<3;c++)bytes[i+c]=255-bytes[i+c]}
          }
        }
        const next=NativeImage.fromRgba(bytes,p.width,p.height);this.image?.dispose();this.image=next;this.imageKey=key;
      }
      buffer.drawImage(this.image,g.x,g.y,g.w,g.h,0,0,0,0,p.width,p.height,"kitty");
      return;
    }
    this.image?.dispose();this.image=null;this.imageKey="";
    for(let y=0;y<g.h;y++)for(let x=0;x<g.w;x++){
      const sx=Math.min(p.width-1,Math.floor(x*p.width/g.w)),top=Math.min(p.height-1,Math.floor(y*p.height/g.h)),bottom=Math.min(p.height-1,Math.floor((y*2+1)*p.height/(g.h*2)));
      buffer.drawText("▀",g.x+x,g.y+y,p.pixels[top*p.width+sx]===TRANSPARENT?checker[check(sx,top)]:colors[p.pixels[top*p.width+sx]],p.pixels[bottom*p.width+sx]===TRANSPARENT?checker[check(sx,bottom)]:colors[p.pixels[bottom*p.width+sx]]);
    }
    if(this.cursor){
      const x=g.x+Math.floor(this.cursor.x*g.w/p.width),y=g.y+Math.floor(this.cursor.y*g.h/p.height);
      const color=p.pixels[this.cursor.y*p.width+this.cursor.x];
      buffer.drawText("+",x,y,color===1?colors[0]:colors[1],color===TRANSPARENT?checker[check(this.cursor.x,this.cursor.y)]:colors[color]);
    }
  }
  protected destroySelf(){this.image?.dispose();this.image=null;super.destroySelf()}
}
extend({paintCanvas:PaintCanvas});
