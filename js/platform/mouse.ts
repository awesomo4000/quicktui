import type { Renderable } from "../../vendor/opentui/packages/core/src/Renderable";
import type { RawMouseEvent, MouseEventType } from "../../vendor/opentui/packages/core/src/lib/parse.mouse";

// Keep the small event contract independent of the Bun-oriented CliRenderer.
class RoutedMouseEvent {
  propagationStopped=false;
  defaultPrevented=false;
  currentTarget:Renderable|null=null;
  readonly type:MouseEventType;
  readonly button:number;
  readonly x:number;
  readonly y:number;
  readonly modifiers:RawMouseEvent["modifiers"];
  readonly scroll:RawMouseEvent["scroll"];
  constructor(readonly target:Renderable, raw:RawMouseEvent){
    this.type=raw.type;this.button=raw.button;this.x=raw.x;this.y=raw.y;
    this.modifiers=raw.modifiers;this.scroll=raw.scroll;
  }
  stopPropagation(){this.propagationStopped=true}
  preventDefault(){this.defaultPrevented=true}
}

export class MouseRouter {
  private hover:Renderable|undefined;
  private captured=new Map<number,Renderable>();
  constructor(private hit:(x:number,y:number)=>Renderable|undefined){}
  reset(){this.hover=undefined;this.captured.clear()}
  private send(target:Renderable|undefined,raw:RawMouseEvent){
    if(target&&!target.isDestroyed)target.processMouseEvent(new RoutedMouseEvent(target,raw) as any);
  }
  dispatch(raw:RawMouseEvent){
    const target=this.hit(raw.x,raw.y);
    if(target!==this.hover){
      this.send(this.hover,{...raw,type:"out"});
      this.hover=target;
      this.send(target,{...raw,type:"over"});
    }
    if(raw.type==="down"&&target)this.captured.set(raw.button,target);
    // Deliver release/drag to the press target even after leaving its bounds.
    const receiver=(raw.type==="drag"||raw.type==="up")?this.captured.get(raw.button)??target:target;
    this.send(receiver,raw);
    if(raw.type==="up")this.captured.delete(raw.button);
  }
}
