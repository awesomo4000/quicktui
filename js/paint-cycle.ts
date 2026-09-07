export type Cycle={start:number,end:number,stepMs:number,direction:number,blend?:boolean};
export const defaultCycle=():Cycle=>({start:10,end:12,stepMs:180,direction:1});
export function validCycle(c:any):c is Cycle{return c&&Number.isInteger(c.start)&&Number.isInteger(c.end)&&c.start>=0&&c.end<32&&c.start<c.end&&Number.isInteger(c.stepMs)&&c.stepMs>=40&&c.stepMs<=2000&&(c.direction===1||c.direction===-1)&&(c.blend===undefined||typeof c.blend==="boolean")}
export function cyclePalette(base:string[],cycle:Cycle,elapsed:number){
 const colors=base.slice(),n=cycle.end-cycle.start+1,phase=elapsed/cycle.stepMs*cycle.direction,step=Math.floor(phase),fraction=phase-step;
 for(let i=0;i<n;i++){
  const at=((i-step)%n+n)%n,next=(at-1+n)%n,a=base[cycle.start+at],b=base[cycle.start+next];
  colors[cycle.start+i]=cycle.blend?"#"+[1,3,5].map(offset=>Math.round(parseInt(a.slice(offset,offset+2),16)*(1-fraction)+parseInt(b.slice(offset,offset+2),16)*fraction).toString(16).padStart(2,"0")).join(""):a;
 }
 return colors;
}
export function testCycle(){
 const blended=cyclePalette(Array(32).fill("#000000").map((c,i)=>i===11?"#ffffff":c),{start:10,end:11,stepMs:100,direction:1,blend:true},50);
 if(blended[10]!=="#808080"||blended[11]!=="#808080")throw new Error("Blend cycle failed");
 const base=Array.from({length:32},(_,i)=>String(i)),c=defaultCycle();
 const a=cyclePalette(base,c,180),b=cyclePalette(base,{...c,direction:-1},180);
 if(a[10]!=="12"||b[10]!=="11"||a[9]!=="9"||base[10]!=="10"||cyclePalette(base,c,540).join()!==base.join())throw new Error("Palette cycle permutation failed");
}
