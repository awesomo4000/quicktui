import {useLayoutEffect,useRef} from "../vendor/js/node_modules/react";
import {subscribeKeyboard,type AppKeyEvent,type InputReset} from "./keyboard";

export interface KeyboardEventOptions {
  /** Receive release events as well as ordinary presses and repeats. */
  realtime?:boolean;
  /** Enable only while this component should handle keys, for example when focused. */
  enabled?:boolean;
  onReset?:(event:InputReset)=>void;
}
/** App onKey runs first, then enabled hooks in subscription order, then widget fallback. */
export function useKeyboardEvents(handler:(event:AppKeyEvent)=>boolean|void,options:KeyboardEventOptions={}){
  const current=useRef({handler,options});
  useLayoutEffect(()=>{current.current={handler,options}});
  useLayoutEffect(()=>{
    if(options.enabled===false)return;
    return subscribeKeyboard(event=>{
      const {handler,options}=current.current;
      if(event.kind==="release"&&!options.realtime)return;
      return handler(event);
    },event=>current.current.options.onReset?.(event));
  },[options.enabled!==false]);
}
