export const WORLD=64, FLOOR=12;
export class PlatformGame {
 x=2;y=11;vy=0;grounded=true;deaths=0;won=false;
 solid(x:number,y:number){
  if(x<0||x>=WORLD)return true;
  if(y>=FLOOR)return !((x>=23&&x<=26)||(x>=45&&x<=48));
  return (x===19||x===20||x===30||x===31)&&y>=10;
 }
 overlaps(x:number,y:number){
  const left=Math.floor(x),right=Math.floor(x+.8-1e-7);
  const top=Math.floor(y),bottom=Math.floor(y+.9-1e-7);
  return this.solid(left,top)||this.solid(right,top)||this.solid(left,bottom)||this.solid(right,bottom);
 }
 reset(){this.x=2;this.y=11;this.vy=0;this.grounded=true;this.won=false}
 jump(){if(this.grounded&&!this.won){this.vy=-12;this.grounded=false}}
 step(dt:number,direction:number,jump:boolean,release:boolean){
  if(this.won)return;
  if(jump)this.jump();if(release&&this.vy< -4)this.vy=-4;
  // Small axis-separated substeps prevent tunnelling through one-cell obstacles.
  const steps=Math.max(1,Math.ceil(dt/.008));dt/=steps;
  for(let i=0;i<steps;i++){
   const x=this.x+direction*10*dt;
   if(!this.overlaps(x,this.y))this.x=x;
   this.vy=Math.min(22,this.vy+28*dt);const y=this.y+this.vy*dt;
   if(this.overlaps(this.x,y)){
    if(this.vy>0){this.y=Math.floor(y+.9-1e-7)-.9;this.grounded=true;}
    else if(this.vy<0){this.y=Math.floor(y)+1;}
    this.vy=0;
   }else{this.y=y;this.grounded=false}
   if(this.y>16||(Math.floor(this.x)===37&&this.y>10)){this.deaths++;this.reset();return}
   if(this.x>60&&this.y>9){this.won=true;return}
  }
 }
}
