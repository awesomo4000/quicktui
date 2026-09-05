import { resolveRenderLib } from "../../vendor/opentui/packages/core/src/zig";
import stripAnsi from "../../vendor/js/node_modules/strip-ansi";
export const stripANSI = stripAnsi;
export const sleep = (ms: number) => new Promise(resolve=>setTimeout(resolve,ms));
export function stringWidth(text: string) {
  const lib=resolveRenderLib();
  const encoded=lib.encodeUnicode(stripAnsi(text),"unicode");
  if(!encoded) return 0;
  try { return encoded.data.reduce((sum,cell)=>sum+cell.width,0); }
  finally { lib.freeUnicode(encoded); }
}
export function writeFile(): never { throw new Error("File writing is not supported by the counter profile"); }
export function resolveBundledFilePath(): never { throw new Error("Runtime assets are not supported by the counter profile"); }
