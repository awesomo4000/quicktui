import {Renderable} from "../vendor/opentui/packages/core/src/Renderable";
import {RGBA} from "../vendor/opentui/packages/core/src/lib/RGBA";
import {extend} from "./platform/catalogue";
const FG=RGBA.fromHex("#eee9dc"),BG=RGBA.fromHex("#000000");
export class LabCells extends Renderable {
  private _pixels:Uint8Array|null=null;
  private _mode="half";
  public glyphs="";
  public glyphCols=0;
  public glyphRows=0;
  constructor(ctx:any,options:any){super(ctx,options);this._pixels=options.pixels;this._mode=options.mode??"half";this.glyphs=options.glyphs??"";this.glyphCols=options.glyphCols??0;this.glyphRows=options.glyphRows??0}
  set pixels(value:Uint8Array){this._pixels=value;this.requestRender()}
  set mode(value:string){this._mode=value;this.requestRender()}
  protected renderSelf(buffer:any){
    if(this._mode==="glyphs"){
      const left=this.x+Math.max(0,Math.floor((this.width-this.glyphCols)/2));
      const top=this.y+Math.max(0,Math.floor((this.height-this.glyphRows)/2));
      const lines=this.glyphs.split("\n");
      for(let y=0;y<Math.min(this.height,this.glyphRows);y++)buffer.drawText(lines[y]??"",left,top+y,FG,BG);
      return;
    }
    const data=this._pixels;if(!data)return;
    const cols=Math.max(1,Math.min(this.width,Math.floor(this.height*3)));
    const rows=Math.max(1,Math.min(this.height,Math.floor(cols/3)));
    const left=this.x+Math.floor((this.width-cols)/2),top=this.y+Math.floor((this.height-rows)/2);
    const sample=(x:number,y:number,w:number,h:number)=>{
      const sx=Math.min(239,Math.floor(x*240/w)),sy=Math.min(159,Math.floor(y*160/h));
      const i=(sy*240+sx)*4;
      return [data[i],data[i+1],data[i+2]];
    };
    if(this._mode==="braille"){
      const bits=[[0,3],[1,4],[2,5],[6,7]];
      for(let y=0;y<rows;y++){
        let line="";
        for(let x=0;x<cols;x++){
          let mask=0;
          for(let dy=0;dy<4;dy++)for(let dx=0;dx<2;dx++){
            const c=sample(x*2+dx,y*4+dy,cols*2,rows*4);
            if(c[0]*.299+c[1]*.587+c[2]*.114>90)mask|=1<<bits[dy][dx];
          }
          line+=mask?String.fromCodePoint(0x2800+mask):" ";
        }
        buffer.drawText(line,left,top+y,FG,BG);
      }
    }else{
      for(let y=0;y<rows;y++)for(let x=0;x<cols;x++){
        const a=sample(x,y*2,cols,rows*2),b=sample(x,y*2+1,cols,rows*2);
        buffer.drawText("▀",left+x,top+y,RGBA.fromInts(a[0],a[1],a[2],255),RGBA.fromInts(b[0],b[1],b[2],255));
      }
    }
  }
}
extend({labCells:LabCells});
