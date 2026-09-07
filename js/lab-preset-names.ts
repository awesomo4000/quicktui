// Older files did not record whether their description was generated.
export function automaticName(entry:{description:string,description_auto?:boolean|null}){
  return entry.description_auto ?? (!entry.description || /^(Torus|Orb|Sheet|4D hypercube|Mandelbrot) \/ (Color|Grayscale|Screen Bayer|Surface fractal|Surface fractal color|Surface fractal wash|Surface two-shade)$/.test(entry.description));
}
// Canonical saved settings: viewport dimensions and transport epoch are not settings.
// Round native f32 fields before hashing so saving/loading keeps the fingerprint.
export function settingsHash(scene:any,output:number,glyph:number){
  const defaults:any={shape:0,angle:0,tilt:.7,zoom:.82,wire:false,palette:0,playing:true,fps:10,rotation_speed:1,tone:0,wash_strength:.3,dark_ink:.15,brightness:0,contrast:1,dot_scale:4,fractal_zoom:1,center_x:-.65,center_y:0};
  const floats=new Set(["tilt","zoom","rotation_speed","wash_strength","dark_ink","brightness","contrast","dot_scale"]);
  const values=Object.keys(defaults).sort().map(key=>{
    const value=scene[key]??defaults[key];
    return [key,floats.has(key)?Math.fround(value):value];
  });
  const text=JSON.stringify([values,output,glyph]);
  let hash=0xcbf29ce484222325n;
  for(const byte of new TextEncoder().encode(text))hash=BigInt.asUintN(64,(hash^BigInt(byte))*0x100000001b3n);
  return hash.toString(16).padStart(16,"0").slice(-10);
}
export function presetName(scene:any,shape:string,tone:string,output:string,outputMode=0,glyph=1){
  const shortShape=shape==="4D hypercube"?"4D cube":shape;
  const shortTone=tone.replace("Surface fractal","Fractal").replace("Surface two-shade","Two-shade");
  return `${shortShape} / ${shortTone} / ${output} #${settingsHash(scene,outputMode,glyph)}`;
}
