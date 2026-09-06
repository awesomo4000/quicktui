// All negative cases use pool-owned disposable memory or non-address values.
globalThis.__selfTest = function () {
  const n = __native;
  const check = (ok, message) => { if (!ok) throw new Error(message); };
  const rejects = (fn) => { let failed=false;try{fn()}catch(_){failed=true}check(failed,"Expected rejected buffer-view operation"); };
  const create = () => n.createOptimizedBuffer(4, 2, 0, 0, new Uint8Array([116]), 1);
  const first = create();
  const getters = ["bufferGetCharPtr","bufferGetFgPtr","bufferGetBgPtr","bufferGetAttributesPtr"];
  const views = getters.map(name => n[name](first));
  for (let i=0;i<views.length;i++) {
    const view=views[i], length=8*([1,2].includes(i)?8:4);
    check(typeof view === "object", "Native address escaped as a number");
    check(__readBufferView(view,0,length).byteLength===length,"Incorrect plane length");
    check(__readBufferView(view,length,0).byteLength===0,"Empty end slice failed");
    rejects(()=>__readBufferView(view,0,length+1));
    rejects(()=>__readBufferView(view,-1,1));
    rejects(()=>__readBufferView(view,0.5,1));
    rejects(()=>__readBufferView(view,NaN,1));
    rejects(()=>__readBufferView(view,Number.MAX_SAFE_INTEGER,1));
    rejects(()=>__readBufferView({},0,1));
    rejects(()=>__readBufferView(Object.create(Object.getPrototypeOf(view)),0,1));
    rejects(()=>__readBufferView(0n,0,1));
  }
  n.bufferResize(first,2,2);
  views.forEach(view=>rejects(()=>__readBufferView(view,0,1)));
  const resized=n.bufferGetCharPtr(first);
  check(__readBufferView(resized,0,16).byteLength===16,"Resized buffer read failed");
  n.destroyOptimizedBuffer(first);
  rejects(()=>__readBufferView(resized,0,1));
  const second=create();
  check(__readBufferView(n.bufferGetCharPtr(second),0,32).byteLength===32,"Replacement buffer failed");
  rejects(()=>__readBufferView(resized,0,1));
  n.destroyOptimizedBuffer(second);
};
// This fixture has no React effects or key subscriptions to tear down.
globalThis.__inspect = () => JSON.stringify({effectMounted:false,keys:0});
