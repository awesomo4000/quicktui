import {existsSync} from "node:fs";
import path from "node:path";
export interface BundleOptions {entry:string;output:string;demoAssets?:boolean;sourcemap?:"none"|"external";}
export async function bundleApp(options:BundleOptions){
const base=path.resolve(import.meta.dir,"..");
const entry=path.resolve(options.entry);
const paint=!options.demoAssets;
const native=path.join(base,"vendor/opentui/packages/core/src");
const react=path.join(base,"vendor/opentui/packages/react/src");
const platform=path.join(base,"js/platform");
const replacements=new Map([
  [path.join(native,"platform/ffi.ts"),path.join(platform,"ffi.ts")],
  [path.join(native,"platform/runtime.ts"),path.join(platform,"runtime.ts")],
  [path.join(react,"components/index.ts"),path.join(platform,"catalogue.ts")],
]);
const picture=paint?"":Buffer.from(await Bun.file(path.join(base,"assets/dragon.jpg")).arrayBuffer()).toString("base64");
const spriteFrames=paint?[]:await Promise.all(Array.from({length:8},async(_,i)=>Buffer.from(await Bun.file(path.join(base,`assets/dragon-frames/${i}.rgba`)).arrayBuffer()).toString("base64")));
const result=await Bun.build({
  entrypoints:["quicktui:entry"],target:"browser",format:"iife",minify:false,sourcemap:options.sourcemap??"none",
  define:{"__SPRITE_FRAMES_BASE64__":JSON.stringify(spriteFrames),"__DEMO_PICTURE_BASE64__":JSON.stringify(picture),"process.env.NODE_ENV":'"production"',"process.env.DEV":'"false"'},
  plugins:[{name:"quicktui-shared-runtime",setup(build){
    build.onResolve({filter:/.*/},async(args)=>{
      if(args.path==="quicktui:entry")return {path:"entry",namespace:"quicktui-entry"};
      if(args.path==="quicktui")return {path:path.join(base,"js/app.ts")};
      if(args.path==="quicktui/testing")return {path:path.join(base,"js/testing.ts")};
      if(args.path==="quicktui/widgets")return {path:path.join(platform,"core.ts")};
      if(args.path==="react"||args.path.startsWith("react/"))return {path:Bun.resolveSync(args.path,path.join(base,"vendor/js"))};
      if(args.path === entry) return {path:entry};
      if(args.path==="@opentui/core")return {path:path.join(platform,"core.ts")};
      if(["events","node:events","buffer","node:buffer"].includes(args.path))return {path:path.join(base,"vendor/js/node_modules",args.path.replace("node:",""),args.path.endsWith("events")?"events.js":"index.js")};
      if(args.path==="node:util")return {path:"util",namespace:"quicktui"};
      if(args.path==="#opentui/runtime-assets")return {path:"assets",namespace:"quicktui"};
      if(["fs","node:fs","node:fs/promises"].includes(args.path)&&!args.importer.startsWith(native+path.sep))throw new Error(`Unsupported host import ${args.path} from ${args.importer}`);
      if(["fs","node:fs"].includes(args.path))return {path:"fs",namespace:"quicktui"};
      if(args.path==="node:fs/promises")return {path:"fs-promises",namespace:"quicktui"};
      if(args.path.startsWith("node:") || args.path.startsWith("bun:"))throw new Error(`Unsupported host import ${args.path} from ${args.importer}`);
      if(!args.path.startsWith(".")&&!path.isAbsolute(args.path)){
        return {path:Bun.resolveSync(args.path,path.join(base,"vendor/js"))};
      }
      let resolved=path.resolve(args.resolveDir,args.path);
      if(resolved.endsWith(".js"))resolved=resolved.slice(0,-3)+".ts";
      else if(!path.extname(resolved))resolved+=".ts";
      if(resolved===path.join(native,"lib/tree-sitter/index.ts"))return {path:path.join(platform,"plain-code.ts")};
      if(replacements.has(resolved))return {path:replacements.get(resolved)!};
      return {path:existsSync(resolved)?resolved:Bun.resolveSync(args.path,args.resolveDir)};
    });
    build.onLoad({filter:/.*/,namespace:"quicktui-entry"},()=>({loader:"js",resolveDir:base,contents:`if(typeof __host!=="undefined")require(${JSON.stringify(path.join(platform,"bootstrap.ts"))});require(${JSON.stringify(entry)});export {};`}));
    build.onLoad({filter:/.*/,namespace:"quicktui"},args=>({loader:"ts",contents:args.path==="assets"?'export const resolveNativeLibraryPath=()=>"quicktui:static";':args.path==="fs-promises"?'export function open(){throw new Error("File image loading is unsupported; use NativeImage pixels")};export const stat=open;':args.path==="util"?'export const inspect=Object.assign((value)=>String(value),{custom:Symbol.for("nodejs.util.inspect.custom")}); export default {inspect};':'export function existsSync(){throw new Error("Filesystem access is unsupported")}; export function writeFileSync(){throw new Error("Filesystem access is unsupported")};'}));
    build.onLoad({filter:/lib\/tree-sitter\/resolve-ft\.ts$/},async args=>({loader:"ts",contents:(await Bun.file(args.path).text()).replace('import path from "node:path"','const path={posix:{basename:(s:string)=>s.split("/").filter(Boolean).pop()??""}};')}));
    build.onLoad({filter:/packages\/core\/src\/zig\.ts$/},async(args)=>{
      let source=await Bun.file(args.path).text();
      source=source.replace(/let targetLibPath:[\s\S]*?(?=registerEnvVar\()/,'const targetLibPath="quicktui:static"; const targetLibError=undefined;\n');
      // The native registry owns the profile. Avoid retaining the 423-entry table.
      const start=source.indexOf("const rawSymbols = dlopen(");
      const end=source.indexOf("if (env.OTUI_DEBUG_FFI",start);
      source=source.slice(0,start)+'const rawSymbols=dlopen(resolvedLibPath, {});\n\n  '+source.slice(end);
      return {contents:source,loader:"ts"};
    });
    build.onLoad({filter:/packages\/core\/src\/lib\/index\.ts$/},()=>({loader:"ts",contents:['border','RGBA','styled-text','extmarks'].map(name=>`export * from "./${name}.js";`).join("\n")}));
    build.onLoad({filter:/bun-ffi-structs\/dist\/index\.js$/},async(args)=>{
      const source=await Bun.file(args.path).text();
      const start=source.indexOf("// src/structs_ffi.ts");
      return {loader:"js",contents:`import {ptr,toArrayBuffer} from ${JSON.stringify(path.join(platform,"ffi.ts"))};\n`+source.slice(start)};
    });
  }}],
});
if(!result.success)throw new AggregateError(result.logs,"QuickTUI application bundle failed");
const licenses=await Promise.all(["react","react-reconciler","scheduler","events","buffer","bun-ffi-structs","base64-js","ieee754","strip-ansi","ansi-regex","diff","marked"].map(async name=>{
  for(const file of ["LICENSE","LICENSE.md","license"]){const f=Bun.file(path.join(base,`vendor/js/node_modules/${name}/${file}`));if(await f.exists())return `${name}\n${await f.text()}`}
  throw new Error(`Missing license for ${name}`);
}));
licenses.push(`OpenTUI\n${await Bun.file(path.join(base,"vendor/opentui/LICENSE")).text()}`);
const bundled=(await result.outputs[0].text()).replace(/\/\/# sourceMappingURL=.*$/m,"//# sourceMappingURL="+path.basename(options.output)+".map");
// Guard the shared graph against accidentally reintroducing per-demo copies.
for(const module of ["vendor/js/node_modules/react/cjs/react.production.js","vendor/js/node_modules/react-reconciler/cjs/react-reconciler.production.js","vendor/opentui/packages/core/src/zig.ts"]){
  const count=bundled.split(`${module}\n`).length-1;
  if(count>1||(options.demoAssets&&count!==1))throw new Error(`Expected at most one shared copy of ${module}, got ${count}`);
}
const banner=`/*!\n${licenses.join("\n")}\n*/\n`;
// Account for the license banner in external source maps.
const header=banner;
await Bun.write(options.output,header+bundled);
for(const artifact of result.outputs)if(artifact.kind==="sourcemap"){
  const map=JSON.parse(await artifact.text());map.mappings=";".repeat(header.split("\n").length-1)+map.mappings;
  await Bun.write(options.output+".map",JSON.stringify(map));
}
}
if(import.meta.main){
 const [entry,output]=process.argv.slice(2);
 if(!entry||!output)throw new Error("Usage: bun scripts/bundle-app.ts <entry.tsx> <output.js>");
 await bundleApp({entry,output});
}
