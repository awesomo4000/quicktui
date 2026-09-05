import React, {useEffect, useState} from "../vendor/js/node_modules/react";

const palette=[[99,199,178],[133,156,225],[181,136,207],[224,168,101],[94,183,205]];
function tint(color:number[],amount:number){
  const background=[16,24,32];
  return "#"+color.map((channel,i)=>Math.round(background[i]+(channel-background[i])*amount).toString(16).padStart(2,"0")).join("");
}
const verbs=["thinking...","connecting...","considering...","imagining...","remembering...","reconsidering..."];

// A purely visual React animation, independent of the worker and its heartbeat.
export function Activity(){
  const [size,setSize]=useState({width:24,height:8});
  const [time,setTime]=useState(0);
  useEffect(()=>{
    const started=Date.now();
    const timer=setInterval(()=>setTime((Date.now()-started)/1000),50);
    return()=>clearInterval(timer);
  },[]);
  const columns=Math.max(1,Math.floor((size.width-4)/3));
  const rows=Math.max(1,Math.min(12,size.height-4));
  const cycle=time/2.8;
  const fade=Math.pow(Math.sin(Math.PI*(cycle%1)),1.4);
  const signal=512+240*Math.sin(time*0.63)+71*Math.sin(time*1.71);
  const coherence=0.5+0.35*Math.sin(time*0.37+1.4);
  return <box id="message-activity" flexGrow={1} minHeight={0} border borderColor="#36535f" title=" Activity " paddingX={1} overflow="hidden"
    onSizeChange={function(this:{width:number,height:number}){setSize({width:this.width,height:this.height})}}>
    {Array.from({length:rows},(_,y)=><box key={y} height={1} flexShrink={0} flexDirection="row" gap={1}>
      {Array.from({length:columns},(_,x)=>{
        const wave=(1+Math.sin(time*(1.2+(x%3)*0.13)-x*0.7+y*1.1))/2;
        const shimmer=(1+Math.sin(time*2.3+x*1.7+y*0.6))/2;
        const brightness=0.12+0.88*Math.pow(wave*0.8+shimmer*0.2,2);
        return <box key={x} width={2} height={1} flexShrink={0} backgroundColor={tint(palette[(x+2*y)%palette.length],brightness)}/>;
      })}
    </box>)}
    <text height={1} flexShrink={0} fg={tint([164,205,213],fade)}>{verbs[Math.floor(cycle)%verbs.length]}</text>
    <text height={1} flexShrink={0} fg={tint([120,157,177],0.55+0.3*Math.sin(time*0.9)**2)}>{signal.toFixed(1)}  /  {coherence.toFixed(3)}</text>
  </box>;
}
