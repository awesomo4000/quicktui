declare const __native: Record<string, Function>;
declare function __pointer(value: ArrayBuffer | ArrayBufferView): bigint;
declare function __readMemory(pointer: bigint, length: number): ArrayBuffer;
declare function __callback(kind: number, fn: Function | null): bigint;

export const ptr = __pointer;
export const usesBunFFI = false;
export const suffix = "static";
export const toPointer = (value: number | bigint) => BigInt(value);
export const ffiBool = (value: boolean) => value ? 1 : 0;
export const trimNodeFFIOutputBytes = (bytes: Uint8Array, length: number) => bytes.slice(0,length);
// Copy native read results. No JavaScript view can outlive a native allocation.
export const toArrayBuffer = (pointer: bigint, offset = 0, length: number) => __readMemory(BigInt(pointer)+BigInt(offset),length);
const kinds = ["u8,ptr,u32", "ptr,u32,ptr,u32", "ptr,f32,u32,f32,u32", "ptr"];
export function dlopen(path: string) {
  if(path !== "quicktui:static") throw new Error("Only the statically linked QuickTUI registry is supported");
  const active = new Set<{close():void}>();
  return {
    symbols: new Proxy(__native, { get(target,key: string) {
      if (!(key in target)) throw new Error(`Unsupported native operation in counter profile: ${key}`);
      return target[key];
    }}),
    createCallback(fn: Function, signature: {args:string[],returns:string,threadsafe?:boolean}) {
      const kind=kinds.indexOf(signature.args.join(","));
      if(kind<0 || signature.returns!=="void" || signature.threadsafe) throw new Error("Unsupported native callback signature");
      let pointer: bigint | null=__callback(kind,fn);
      const callback={get ptr(){return pointer},threadsafe:false,close(){if(pointer!==null){__callback(kind,null);pointer=null;active.delete(callback)}}};
      active.add(callback);
      return callback;
    },
    close(){for(const callback of [...active]) callback.close()},
  };
}
