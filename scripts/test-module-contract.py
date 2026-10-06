#!/usr/bin/env python3
"""Supported ES-module contract, with safe rejection fixtures under /tmp."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--quicktui', type=Path, default=root/'zig-out/bin/quicktui')
parser.add_argument('--pack-tool', type=Path, default=root/'zig-out/bin/quicktui-pack')
args = parser.parse_args()
exe = args.quicktui.resolve()
pack_tool = args.pack_tool.resolve()
with tempfile.TemporaryDirectory(prefix='quicktui-contract-', dir='/tmp') as directory:
    work = Path(directory).resolve()
    env = dict(os.environ, QUICKTUI_CACHE=str(work/'cache'))
    def write(name, code):
        path=work/name; path.parent.mkdir(parents=True,exist_ok=True);path.write_text(code)
    def run(command, error=None):
        result=subprocess.run(list(map(str,command)),cwd=work,env=env,capture_output=True,text=True,timeout=45)
        output=result.stdout+result.stderr
        assert (result.returncode==0)==(error is None),output
        if error: assert error in output,output
    app=work/'app.ts'
    source=[exe,'--run',app,'--app-root',work,'--self-test']
    pack=[pack_tool,root,app,work/'app.pack','--app-root',work]
    tail='''
import React from "react";
import {createApplication} from "quicktui/core";
import {testApp} from "quicktui/testing";
if(typeof React.createElement!=="function")throw Error("React compatibility");
const app=createApplication();testApp(async ui=>{await ui.resize(80,24)});
'''
    write('plain.js','globalThis.plainLoaded=true;')
    write('value.ts','export default 42;')
    write('app.ts','''import './plain.js';import value from './value';
const require=(x:number)=>x;const module={value};const exports={value};
if(require(42)!==42||module.value!==42||exports.value!==42||!globalThis.plainLoaded)throw Error("local binding");
''' + tail)
    run(source);run(pack);run([exe,'--run-pack',work/'app.pack','--self-test'])
    for code in ['require("./value")', 'if(false)require("./value")',
                 'const r=require; r("./value")', 'module.exports=42', 'exports.answer=42',
                 'import answer = require("./value"); console.log(answer);']:
        write('app.ts',code+';'+tail)
        run(source,'Unsupported application CommonJS');run(pack,'Unsupported application CommonJS')
    write('legacy.cjs','throw Error("must not execute");')
    write('app.ts','import "./legacy.cjs";'+tail)
    run(source,'Unsupported application CommonJS');run(pack,'Unsupported application CommonJS')
    write('node_modules/dual/package.json',json.dumps({'exports':{'import':'./esm.js','require':'./cjs.cjs'}}))
    write('node_modules/dual/esm.js','export default 42;')
    write('node_modules/dual/cjs.cjs','module.exports=42;')
    write('app.ts','import answer from "dual"; console.log(answer);'+tail)
    run(source,'Unsupported conditional package exports');run(pack,'Unsupported conditional package exports')
    write('app.ts','import answer from "./node_modules/dual"; console.log(answer);'+tail)
    run(source,'Unsupported conditional package exports');run(pack,'Unsupported conditional package exports')
    print('Module contract passed: ES imports, React compatibility, local names, explicit unsupported-feature errors')
