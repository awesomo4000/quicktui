#!/usr/bin/env python3
"""Run selected pinned Bun fixtures through QuickTUI; Bun is not required."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
reference = root/'tests/reference/bun'
manifest = json.loads((reference/'fixtures.json').read_text())
for name, digest in manifest['sha256'].items():
    assert hashlib.sha256((reference/'upstream'/name).read_bytes()).hexdigest() == digest, name
known_gaps = {
    'packagejson/ExportsRequireOverImport': 'require condition selection',
    'default/DefineOptionalChain': 'optional/computed define access; upstream TODO',
}
failures = []
with tempfile.TemporaryDirectory(prefix='quicktui-bun-reference-', dir='/tmp') as directory:
    work = Path(directory).resolve()
    def write(base, name, text):
        # Upstream uses synthetic absolute paths. Never write them literally.
        relative = PurePosixPath(name.lstrip('/'))
        assert '..' not in relative.parts and str(relative) != '.', name
        path = base.joinpath(*relative.parts)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path
    def run(args, base):
        result = subprocess.run(list(map(str, args)), cwd=base,
            env=dict(os.environ, QUICKTUI_CACHE=str(base/'cache')),
            capture_output=True, text=True, timeout=60)
        return result.returncode, result.stdout + result.stderr
    for index, fixture in enumerate(manifest['fixtures']):
        name, case = fixture['name'], fixture['case']
        base = work/str(index)
        base.mkdir()
        expected = case.get('run', {}).get('stdout', '')
        write(base, 'capture.mjs', 'globalThis.__referenceLines=[];console.log=(...xs)=>globalThis.__referenceLines.push(xs.map(String).join(" "));')
        imports = 'import "./capture.mjs";\n'
        if 'define' in case:
            write(base, 'adapter.mjs', (root/'vendor/sucrase/sucrase.js').read_text())
            imports += 'import "./adapter.mjs";\n'
            setup = case['runtimeFiles']['/test.js']
            # Both pinned fixtures install globals then import the built output.
            suffix = "await import('./out.js');"
            assert setup.count(suffix) == 1
            setup = setup.replace(suffix, '')
            body = f'''{setup}
try {{
 (0,eval)(globalThis.__sucrase.rewriteDefines({json.dumps(case['files']['/entry.js'])},{{}},{json.dumps(case['define'])}));
}} catch(error) {{ throw Error("REFERENCE_MISMATCH: " + error); }}
'''
        else:
            for path, text in case['files'].items():
                write(base, path, text)
            entry = next(path for path in case['files'] if path.endswith('/src/entry.js'))
            imports += 'import ' + json.dumps('./' + entry.lstrip('/')) + ';\n'
            body = ''
        wrapper = imports + '''import {createApplication} from "quicktui/core";
import {testApp} from "quicktui/testing";
''' + body + f'''
const actual=globalThis.__referenceLines.join("\\n");
if(actual!=={json.dumps(expected)})throw Error("REFERENCE_MISMATCH: "+JSON.stringify(actual));
const app=createApplication();testApp(async ui=>{{await ui.resize(80,24)}});
'''
        app = write(base, 'app.mjs', wrapper)
        source = [root/'zig-out/bin/quicktui','--run',app,'--app-root',base,'--self-test']
        pack = base/'test.pack'
        build = [root/'zig-out/bin/quicktui-pack',root,app,pack,'--app-root',base]
        results = [('source', *run(source, base)), ('pack-build', *run(build, base))]
        if results[-1][1] == 0:
            results.append(('pack', *run([root/'zig-out/bin/quicktui','--run-pack',pack,'--self-test'], base)))
        if 'bundleErrors' in case:
            ok = len(results) == 2 and all(code != 0 and ('not exported' in output or 'Cannot resolve exported target' in output)
                                          for _, code, output in results)
            status = 'PASS rejection' if ok else 'FAIL'
        elif name in known_gaps:
            ok = len(results) == 3 and results[1][1] == 0 and all(
                code != 0 and 'REFERENCE_MISMATCH' in output for mode, code, output in results if mode != 'pack-build')
            status = 'XFAIL ' + known_gaps[name] if ok else 'FAIL unexpected result'
        else:
            ok = len(results) == 3 and all(code == 0 for _, code, _ in results)
            status = 'PASS' if ok else 'FAIL'
        print(f'{name}: {status}', flush=True)
        if not ok:
            failures.append(name)
            for mode, code, output in results:
                print(f'{mode}: exit {code}\n{output[-3000:]}', flush=True)
if failures:
    raise SystemExit(f'{len(failures)} unexpected reference results')
print('Reference checks: 8 passed, 2 documented expected failures; 10 selected cases only')
