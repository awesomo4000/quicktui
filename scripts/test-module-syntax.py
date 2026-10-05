#!/usr/bin/env python3
"""Parser/scope regressions through the actual QuickJS source and pack loaders."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
exe = root / 'zig-out/bin/quicktui'
tool = root / 'zig-out/bin/quicktui-pack'
with tempfile.TemporaryDirectory(prefix='quicktui-syntax-', dir='/tmp') as directory:
    work = Path(directory).resolve()
    env = dict(os.environ, QUICKTUI_CACHE=str(work/'cache'))
    def write(name, text):
        (work/name).write_text(text)
    def run(command):
        result = subprocess.run(list(map(str, command)), cwd=work, env=env,
                                capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, result.stdout + result.stderr
    write('local.ts', 'export const process={env:{NODE_ENV:"local"}};')
    write('bound.ts', '''import {process} from "./local";
if(process.env.NODE_ENV!=="local")throw Error("import binding replaced");
export const value=process.env.NODE_ENV;''')
    write('top.ts', '''const process={env:{NODE_ENV:"top"}};
if(process.env.NODE_ENV!=="top")throw Error("top-level binding replaced");
export const value=process.env.NODE_ENV;''')
    write('value.cjs', 'module.exports=42;')
    write('cjs.cjs', r'''// require("./missing-comment")
const text='require("./missing-string")';
module.exports=require('./val\u0075e.cjs');''')
    write('adapter.mjs', (root/'vendor/sucrase/sucrase.js').read_text())
    write('app.tsx', r'''
import './adapter.mjs';
import {createApplication} from "quicktui/core";
import {testApp} from "quicktui/testing";
import {value as bound} from "./bound";
import {value as top} from "./top";
import cjs from "./cjs.cjs";
function eq(actual:any, expected:any){if(actual!==expected)throw Error(JSON.stringify({actual,expected}));}
declare const __DEMO_PICTURE_BASE64__: string;
declare const process:any;
eq(process.env.NODE_ENV,"production");
eq(process /* keep comment */ . env . NODE_ENV,"production");
eq(process.env.DEV,"false");
eq('process.env.NODE_ENV', 'process' + '.env.NODE_ENV');
eq("__DEMO_PICTURE_BASE64__", '__DEMO_' + 'PICTURE_BASE64__');
eq(/process.env.NODE_ENV/.source, 'process' + '.env.NODE_ENV');
eq(`process.env.NODE_ENV ${process.env.NODE_ENV}`, 'process' + '.env.NODE_ENV production');
eq((<text title="process.env.NODE_ENV">{process.env.NODE_ENV}</text>).props.children,"production");
eq((<text>process.env.NODE_ENV</text>).props.children,'process' + '.env.NODE_ENV');
eq(({__DEMO_PICTURE_BASE64__}).__DEMO_PICTURE_BASE64__, "");
const object={process:{env:{NODE_ENV:"member"}}};eq(object.process.env.NODE_ENV,"member");
function argument(process:any){return process.env.NODE_ENV;}
eq(argument({env:{NODE_ENV:"argument"}}),"argument");
function destructure({process}:any){return process.env.NODE_ENV;}
eq(destructure({process:{env:{NODE_ENV:"destructured"}}}),"destructured");
{const process={env:{NODE_ENV:"block"}};eq(process.env.NODE_ENV,"block");}
try{throw {env:{NODE_ENV:"caught"}}}catch(process){eq(process.env.NODE_ENV,"caught");}
function escaped(pr\u006fcess:any){return process.env.NODE_ENV;}
eq(escaped({env:{NODE_ENV:"escaped"}}),"escaped");
function hoisted(){const read=()=>process.env.NODE_ENV; var process={env:{NODE_ENV:"hoisted"}};return read();}
eq(hoisted(),"hoisted");
const named=function process(){return process.env?.NODE_ENV ?? "named"};eq(named(),"named");
eq(bound,"local");eq(top,"top");eq(cjs,42);
// require("./missing-comment")
const fake='require("./missing-string")';
const regex=/require\("missing-regex"\)/;
const template=`require("./missing-template")`;
function local(require:any){return require("./missing-local");}
eq(local(()=>17),17);
const holder={require:()=>23};eq(holder.require("./missing-member"),23);
eq(require('./val\u0075e.cjs'),42);
eq(require('./value.cjs',),42);
eq(`${require('./value.cjs')}`,"42");
const adapter=(globalThis as any).__sucrase;
const source = 'const text="FLAG"; /* FLAG */ const rx=/FLAG/; const value=FLAG;';
eq(adapter.rewriteDefines(source,{}, {FLAG:'42'}),
   'const text="FLAG"; /* FLAG */ const rx=/FLAG/; const value=(42);');
eq(adapter.rewriteDefines('function x(FLAG){return FLAG} const x2=FLAG;',{}, {FLAG:'42'}),
   'function x(FLAG){return FLAG} const x2=(42);');
eq(adapter.rewriteDefines('const process={}; process.env.NODE_ENV;',{}, {'process.env.NODE_ENV':'"production"'}),
   'const process={}; process.env.NODE_ENV;');
eq(adapter.rewriteDefines('process /* keep */ .\n env . NODE_ENV',{}, {'process.env.NODE_ENV':'"production"'}),
   '("production") /* keep */ \n   ');
const requires=adapter.inspectRequires(`
  // require("missing-comment")
  const text='require("missing-string")';
  const regex=/require("missing-regex")/;
  function f(require){require("missing-local")}
  const obj={require(){}};obj.require("missing-member");
  require("./val\\u0075e.cjs");require('./value.cjs',);
  require(dynamic);
`);
eq(JSON.stringify(requires.specifiers),JSON.stringify(['./value.cjs','./value.cjs']));
eq(requires.usesRequire,true);
eq(adapter.inspectRequires('const require=x=>x;require("local")').usesRequire,false);
eq(adapter.inspectRequires('function f(require){require("local")}').usesRequire,false);
const app=createApplication();
testApp(async ui=>{await ui.resize(80,24)});
''')
    command=[exe,'--run',work/'app.tsx','--app-root',work,'--self-test']
    run(command); run(command)
    run([tool,root,work/'app.tsx',work/'app.pack','--app-root',work])
    # The pack must run after its dependency sources are gone.
    for name in ['value.cjs', 'cjs.cjs', 'local.ts', 'top.ts', 'bound.ts', 'app.tsx', 'adapter.mjs']:
        (work/name).unlink()
    run([exe,'--run-pack',work/'app.pack','--self-test'])
    print('Syntax fixtures passed: defines, shadowing, JSX/templates and literal require discovery')
