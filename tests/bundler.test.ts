import {test,expect} from "bun:test";
import {mkdtemp,rm,writeFile,readFile} from "node:fs/promises";
import {tmpdir} from "node:os";
import path from "node:path";
import {bundleApp} from "../scripts/bundle-app";
const entry=path.resolve(import.meta.dir,"../examples/consumer/app.tsx");
test("consumer bundle includes licenses and a matching external source map",async()=>{
 const temp=await mkdtemp(path.join(tmpdir(),"quicktui-bundle-"));
 try{
  const output=path.join(temp,"app.js");await bundleApp({entry,output,sourcemap:"external"});
  const js=await readFile(output,"utf8"),map=JSON.parse(await readFile(output+".map","utf8"));
  expect(js).toContain("MIT License");expect(map.version).toBe(3);expect(map.sources.length).toBeGreaterThan(0);
  expect(map.mappings.startsWith(";")).toBe(true);
 }finally{await rm(temp,{recursive:true,force:true});}
});
test("consumer filesystem and socket imports fail during bundling",async()=>{
 const temp=await mkdtemp(path.join(tmpdir(),"quicktui-bundle-"));
 try{
  for(const name of ["node:fs","fs","node:fs/promises","node:net","bun:ffi"]){
   const file=path.join(temp,"bad.ts");await writeFile(file,`import * as host from ${JSON.stringify(name)}; console.log(host);`);
   let error:any;try{await bundleApp({entry:file,output:path.join(temp,"bad.js")})}catch(e){error=e}
   expect(error).toBeDefined();expect(String(error.errors?.[0]??error)).toContain("Unsupported host import");
  }
 }finally{await rm(temp,{recursive:true,force:true});}
});
