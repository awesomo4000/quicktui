// QT1 fixes both field meanings and renderer semantics. Append fields only.
// Empty fields and missing trailing fields use these permanent defaults.
type Field=readonly [string,"u8"|"f32"|"f64",number,number,number];
const fields:readonly Field[]=[
  ["shape","u8",0,0,4],["output","u8",0,0,3],["glyph","u8",1,1,8],
  ["tone","u8",0,0,6],["palette","u8",0,0,2],["wire","u8",0,0,1],
  ["zoom","f32",.82,.3,8],["tilt","f32",.7,-Infinity,Infinity],
  ["brightness","f32",0,-1,1],["contrast","f32",1,.25,4],["dot_scale","f32",4,0,5],
  ["wash_strength","f32",.3,0,1],["dark_ink","f32",.15,0,.5],
  ["rotation_speed","f32",1,-4,4],["fps","u8",10,1,120],["playing","u8",1,0,1],
  ["fractal_zoom","f64",1,.5,1e10],["center_x","f64",-.65,-4,4],["center_y","f64",0,-4,4],
  ["angle","f64",0,-Infinity,Infinity],
];
const alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
function pack(bytes:Uint8Array){
  let bits=0,value=0,result="";
  for(const byte of bytes){value=(value<<8)|byte;bits+=8;while(bits>=6){bits-=6;result+=alphabet[(value>>>bits)&63]}}
  if(bits)result+=alphabet[(value<<(6-bits))&63];
  return result;
}
function unpack(text:string,size:number){
  if(text.length!==Math.ceil(size*8/6))throw new Error("Truncated settings field");
  const result=new Uint8Array(size);let bits=0,value=0,index=0;
  for(const ch of text){const digit=alphabet.indexOf(ch);if(digit<0)throw new Error("Invalid settings character");value=(value<<6)|digit;bits+=6;if(bits>=8){bits-=8;result[index++]=(value>>>bits)&255}}
  if(pack(result)!==text)throw new Error("Invalid settings padding");
  return result;
}
function checked(field:Field,value:number){
  const [,type,,min,max]=field;
  const normalized=type==="f32"?Math.fround(value):value;
  if(!Number.isFinite(normalized)||normalized<(type==="f32"?Math.fround(min):min)||normalized>(type==="f32"?Math.fround(max):max)||(type==="u8"&&!Number.isInteger(normalized)))throw new Error("Invalid setting: "+field[0]);
  return normalized;
}
export function encodeSettings(scene:any,output:number,glyph:number){
  const values={...scene,output,glyph};
  const parts=fields.map(field=>{
    const [key,type,fallback]=field;
    const value=checked(field,Number(values[key]??fallback));
    if(value===checked(field,fallback))return "";
    const bytes=new Uint8Array(type==="u8"?1:type==="f32"?4:8),view=new DataView(bytes.buffer);
    if(type==="u8")view.setUint8(0,value);else if(type==="f32")view.setFloat32(0,value,true);else view.setFloat64(0,value,true);
    return pack(bytes);
  });
  while(parts.length&&!parts[parts.length-1])parts.pop();
  return ["QT1",...parts].join(".");
}
export function decodeSettings(code:string){
  const [version,...parts]=code.trim().split(".");
  if(version!=="QT1")throw new Error("Unsupported settings version");
  if(parts.length>fields.length)throw new Error("Settings code needs a newer renderer");
  const values:any={};
  fields.forEach((field,index)=>{
    const [key,type,fallback]=field,part=parts[index]??"";
    let value=fallback;
    if(part){const bytes=unpack(part,type==="u8"?1:type==="f32"?4:8),view=new DataView(bytes.buffer);value=type==="u8"?view.getUint8(0):type==="f32"?view.getFloat32(0,true):view.getFloat64(0,true)}
    values[key]=checked(field,value);
  });
  const {output,glyph,...scene}=values;
  scene.wire=!!scene.wire;scene.playing=!!scene.playing;
  return {version:1,description:"Imported settings",scene,output,glyph};
}
export function testSettingsCode(){
  const example={shape:3,tone:6,angle:1.23456789012345,rotation_speed:-1/65536,zoom:7.9,wash_strength:.65,dark_ink:.125,fractal_zoom:1e9,center_x:-.743643887037151};
  const code=encodeSettings(example,3,8),decoded=decodeSettings(code);
  if(encodeSettings(decoded.scene,decoded.output,decoded.glyph)!==code||decoded.scene.angle!==example.angle||decoded.scene.center_x!==example.center_x||decoded.scene.rotation_speed!==example.rotation_speed)throw new Error("Settings code round trip failed");
  if(encodeSettings({},0,1)!=="QT1"||decodeSettings("QT1").scene.fps!==10)throw new Error("Settings defaults failed");
  for(let n=1;n<=code.split(".").length;n++)decodeSettings(code.split(".").slice(0,n).join("."));
  for(const bad of ["QT2","QT1.A","QT1.!!","QT1._w",code+".AA"]){
    let rejected=false;try{decodeSettings(bad)}catch{rejected=true}
    if(!rejected)throw new Error("Invalid settings code accepted");
  }
}
