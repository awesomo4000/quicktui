#!/usr/bin/env python3
"""Safe disposable source-loader fixtures, including bounded hostile compilation."""
import os
from pathlib import Path
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
root = Path(__file__).resolve().parent.parent
exe = root / 'zig-out/bin/quicktui'
tool = root / 'zig-out/bin/quicktui-pack'
with tempfile.TemporaryDirectory(prefix='quicktui-module-edges-') as directory:
    work=Path(directory).resolve()
    env=dict(os.environ,QUICKTUI_CACHE=str(work/'cache'))
    def run(command,ok=True,needle=None,timeout=45):
        result=subprocess.run([str(x) for x in command],env=env,cwd=work,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=timeout)
        output=result.stdout.decode(errors='replace')
        assert (result.returncode==0)==ok, output
        if needle: assert needle in output,output
        return output
    def source(file): return [exe,'--run',file,'--app-root',work,'--self-test']
    (work/'src').mkdir();(work/'shared').mkdir()
    app=work/'src/app.ts'
    helper=work/'shared/value.ts'
    helper.write_text('export const value=42;')
    app.write_text('''import {createApplication} from "quicktui/core";
import {testApp} from "quicktui/testing";
import {value} from "../shared/value";
const app=createApplication();app.root.add(app.text({content:String(value)}));
testApp(async ui=>{await ui.resize(80,24);if(!ui.snapshot().includes("42"))throw Error("wrong helper value")});''')
    run(source(app)); run(source(app))
    # Unchanged entry, changed dependency must invalidate its own cache entry.
    helper.write_text('export const value=99;')
    run(source(app),False,'wrong helper value')
    helper.write_text('export const value=42;')
    # Corruption must rebuild instead of feeding broken cache bytes to QuickJS.
    for cache in (work/'cache').glob('*.qbc'): cache.write_bytes(b'corrupt')
    run(source(app))
    pack=work/'app.pack'
    run([tool,root,app,pack,'--app-root',work])
    assert str(work).encode() not in pack.read_bytes()
    assert str(root).encode() not in pack.read_bytes()
    run([exe,'--run-pack',pack,'--self-test'])
    data=pack.read_bytes()
    # Header/framing mutations only, never fabricated executable bytecode.
    for index,body in enumerate([b'',b'garbage',data[:20],data[:-1]]):
        bad=work/f'bad-{index}.pack';bad.write_bytes(body)
        run([exe,'--run-pack',bad,'--self-test'],False,'module pack rejected')
    (work/'a.ts').write_text('import {b} from "./b"; export const a=1; export function read(){return b;}')
    (work/'b.ts').write_text('import {a} from "./a"; export const b=2; export function read(){return a;}')
    app.write_text('import {read} from "../a"; if(read()!==2)throw Error("cycle");\n'+app.read_text())
    run(source(app))
    (work/'b.ts').write_text('import {a} from "./a"; export const b=a;')
    run(source(app),False)
    app.write_text('import "./missing";')
    run(source(app),False,'Cannot resolve')
    app.write_text('import "./loop.cjs";')
    (work/'src/loop.cjs').write_text('while(true){}')
    # Unsupported CJS must be rejected before executing the hostile body.
    with ThreadPoolExecutor(max_workers=2) as pool:
        tasks=[pool.submit(run,source(app),False,"Unsupported application CommonJS",40),
               pool.submit(run,[tool,root,app,work/'loop.pack','--app-root',work],False,"Unsupported application CommonJS",40)]
        for task in tasks: task.result()
    print('Module edges: app roots, cache invalidation/corruption, cycles, pack framing and CommonJS rejection passed')
