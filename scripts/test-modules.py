#!/usr/bin/env python3
"""Exercise bundle/source/cache/pack parity, or an embedded-only release.

Build first, then run: python3 scripts/test-modules.py [--bin-dir zig-out/bin]
Use --embedded-only with a -Dsource-loader=false build.
All generated files and caches live in a disposable temporary directory.
"""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--bin-dir', type=Path, default=ROOT / 'zig-out/bin')
parser.add_argument('--embedded-only', action='store_true')
args = parser.parse_args()
bin_dir = args.bin_dir.resolve()
flags = ['--self-test'] + [f'--{name}-self-test' for name in
    ['gallery', 'vanilla', 'game', 'keyboard', 'mouse', 'live', 'reload', 'editor', 'lab', 'messages']]
failures = []
base_env = {k: v for k, v in os.environ.items() if not k.startswith('QUICKTUI_')}

with tempfile.TemporaryDirectory(prefix='quicktui-modules-') as directory:
    work = Path(directory)
    def run(label, command, env=None, expect_success=True):
        start = time.monotonic()
        try:
            result = subprocess.run([str(x) for x in command], cwd=ROOT,
                env=base_env | {'QUICKTUI_CACHE': str(work / 'cache')} | (env or {}),
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
            ok = (result.returncode == 0) == expect_success
            output = result.stdout.decode(errors='replace')
        except subprocess.TimeoutExpired as error:
            ok = False
            output = f'Timed out: {error.stdout!r}'
        print(f'{label}: {"PASS" if ok else "FAIL"} ({time.monotonic()-start:.2f}s)', flush=True)
        if not ok:
            failures.append(label)
            print(output[-6000:], flush=True)
        return ok

    if args.embedded_only:
        # These valid files must be ignored, even with hostile environment overrides.
        (work / 'entry.ts').write_text('throw new Error("SOURCE_OVERRIDE_EXECUTED");')
        (work / 'bad.pack').write_bytes(b'not a pack')
        env = {'QUICKTUI_SOURCE': str(work), 'QUICKTUI_PACK': str(work / 'bad.pack')}
        for flag in flags:
            run(f'embedded {flag}', [bin_dir / 'quicktui', flag], env)
        run('embedded paint', [bin_dir / 'termpaint', '--self-test'], env)
        run('embedded smoke', [bin_dir / 'quicktui', '--smoke'], env)
        for option, rest in [('--run', [work / 'entry.ts']), ('--run-pack', [work / 'bad.pack']),
                             ('--build-pack', [work / 'output.pack', work / 'entry.ts'])]:
            run(f'reject {option}', [bin_dir / 'quicktui', option, *rest], env, False)
        assert not (work / 'output.pack').exists()
        assert not (work / 'cache').exists()
    else:
        for name, entry, extra in [('examples', 'js/examples.ts', ['--demo']),
                                   ('paint', 'js/termpaint-entry.ts', []),
                                   ('consumer', 'examples/consumer/app.tsx', [])]:
            if not run(f'build {name}', [bin_dir / 'quicktui', '--build-pack', work / f'{name}.pack', ROOT / entry, *extra]):
                raise SystemExit(1)
        cases = [('quicktui', flag, 'examples') for flag in flags] + [('termpaint', '--self-test', 'paint')]
        for index, (exe, flag, pack) in enumerate(cases):
            cache = str(work / f'cache-{index}')
            for mode in ['bundle', 'cold', 'warm', 'pack']:
                env = {'QUICKTUI_CACHE': cache}
                if mode in ('cold', 'warm'): env['QUICKTUI_SOURCE'] = str(ROOT)
                if mode == 'pack': env['QUICKTUI_PACK'] = str(work / f'{pack}.pack')
                run(f'{exe} {flag} {mode}', [bin_dir / exe, flag], env)
        for app in ['examples/consumer/app.tsx', 'examples/vanilla/app.ts']:
            run(f'source {app}', [bin_dir / 'quicktui', '--run', ROOT / app, '--self-test'])
        run('pack consumer', [bin_dir / 'quicktui', '--run-pack', work / 'consumer.pack', '--self-test'])
print(f'{len(failures)} failures', flush=True)
raise SystemExit(bool(failures))
