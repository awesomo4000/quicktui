#!/usr/bin/env python3
"""Package resolution fixtures in source and pack modes; no Bun required."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--compare-bun', action='store_true', help='also check browser bundle behavior with installed Bun')
args = parser.parse_args()

root = Path(__file__).resolve().parent.parent
exe = root / 'zig-out/bin/quicktui'
tool = root / 'zig-out/bin/quicktui-pack'
with tempfile.TemporaryDirectory(prefix='quicktui-packages-', dir='/tmp') as directory:
    work = Path(directory).resolve()
    env = dict(os.environ, QUICKTUI_CACHE=str(work / 'cache'))
    def write(path, text):
        path = work / path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    def package(name, exports, files):
        base = 'node_modules/' + name + '/'
        write(base + 'package.json', json.dumps({'type': 'module', 'exports': exports}))
        for name, value in files.items():
            write(base + name, 'export default ' + json.dumps(value) + ';')
    def run(command, error=None):
        result = subprocess.run(list(map(str, command)), cwd=work, env=env,
                                capture_output=True, text=True, timeout=45)
        output = result.stdout + result.stderr
        assert (result.returncode == 0) == (error is None), output
        if error:
            assert error in output, output
    def compare_bun(code, ok=True):
        if not args.compare_bun:
            return
        write('src/compare.ts', code)
        write('compare.mjs', """
const result = await Bun.build({entrypoints:['./src/compare.ts'], target:'browser', format:'esm', outdir:'./bundled'});
if (!result.success) { console.error(result.logs); process.exit(1); }
await import('./bundled/compare.js');
""")
        result = subprocess.run(['bun', 'compare.mjs'], cwd=work, capture_output=True, text=True, timeout=30)
        assert (result.returncode == 0) == ok, result.stdout + result.stderr
    tail = '''
import {createApplication} from "quicktui/core";
import {testApp} from "quicktui/testing";
const app=createApplication();
testApp(async ui=>{await ui.resize(80,24)});
'''
    package('local', {'.': {'browser': './browser.js', 'default': './default.js'}},
            {'browser.js': 'browser', 'default.js': 'default'})
    package('@fixture/scoped', './index.js', {'index.js': 'scoped'})
    package('patterns', {'./*': './general/*.js', './deep/*': './specific/*.js',
                         './deep/private/*': None, './exact': './exact.js'},
            {'general/deep/item.js': 'wrong', 'specific/item.js': 'specific',
             'exact.js': 'exact', 'deep/private/secret.js': 'blocked'})
    package('blocked', {'.': './index.js', './secret.js': None},
            {'index.js': 'ok', 'secret.js': 'blocked', 'other.js': 'unexported'})
    package('null-root', None, {'index.js': 'blocked'})
    package('null-condition', {'.': {'browser': None, 'default': './index.js'}}, {'index.js': 'blocked'})
    package('missing-target', './missing.js', {'index.js': 'wrong'})
    package('escape', '../safe.js', {})
    write('node_modules/safe.js', 'export default "safe disposable target";')
    write('src/app.ts', '\n'.join(
        f'import v{i} from {json.dumps(spec)}; if(v{i}!=={json.dumps(value)})throw Error("wrong {spec}");'
        for i, (spec, value) in enumerate([
            ('local', 'browser'), ('@fixture/scoped', 'scoped'),
            ('patterns/deep/item', 'specific'), ('patterns/exact', 'exact')])) + tail)
    source = [exe, '--run', work/'src/app.ts', '--app-root', work, '--self-test']
    pack = [tool, root, work/'src/app.ts', work/'app.pack', '--app-root', work]
    compare_bun((work/'src/app.ts').read_text().removesuffix(tail))
    run(source); run(source); run(pack)
    run([exe, '--run-pack', work/'app.pack', '--self-test'])
    for spec, error in [
        ('blocked/secret.js', 'is not exported'),
        ('blocked/other.js', 'is not exported'),
        ('null-root', 'is not exported'),
        ('null-condition', 'is not exported'),
        ('patterns/deep/private/secret', 'is not exported'),
        ('missing-target', 'Cannot resolve exported target'),
        ('escape', 'Invalid package export target'),
    ]:
        write('src/app.ts', f'import value from {json.dumps(spec)}; console.log(value);' + tail)
        run(source, error); run(pack, error)
        # QuickTUI deliberately treats a root null export as blocked.
        if spec != 'null-root':
            compare_bun((work/'src/app.ts').read_text().removesuffix(tail), False)
    print('Package fixtures passed: local/scoped imports, conditions, patterns, blocked exports and targets')
