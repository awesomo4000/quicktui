#!/usr/bin/env python3
"""Build a pack-only consumer outside the checkout and test closed resolution."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--libc')
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix='quicktui-pack-consumer-') as directory:
    work = Path(directory).resolve()
    for name in ['app.tsx', 'main.zig', 'build.zig', 'build.zig.zon']:
        shutil.copy(root / 'examples/pack-consumer' / name, work / name)
    manifest = work / 'build.zig.zon'
    manifest.write_text(manifest.read_text().replace('"../.."', json.dumps(os.path.relpath(root, work))))
    command = ['zig', 'build', '-Doptimize=ReleaseSmall', '--global-cache-dir', str(root / '.zig-cache/global')]
    if args.libc: command += ['--libc', args.libc]
    subprocess.run(command, cwd=work, check=True, timeout=240)
    executable = work / 'zig-out/bin/consumer'
    # Remove application sources and make a real, safe file that was not packed.
    (work / 'app.tsx').unlink()
    (work / 'not-in-pack.txt').write_text('Filesystem fallback must not read this')
    (work / 'bad.pack').write_bytes(b'not a module pack')
    env = dict(os.environ, QUICKTUI_SOURCE=str(work), QUICKTUI_PACK=str(work / 'bad.pack'), QUICKTUI_CACHE=str(work / 'cache'))
    subprocess.run([executable, '--self-test'], cwd=work, env=env, check=True, timeout=60)
    assert not (work / 'cache').exists(), 'Release created a module cache'
    if shutil.which('nm'):
        symbols = subprocess.check_output(['nm', str(executable)], text=True)
        for symbol in ['qt_fs_read', 'qt_fs_write', 'qt_fs_is_file', 'qt_cache_get', 'qt_cache_put', 'quicktui_build_pack']:
            assert symbol not in symbols, f'Release contains {symbol}'
    data = executable.read_bytes()
    assert b'__loaderPolicy' not in data, 'Release contains transpiler'
    assert str(work).encode() not in data, 'Release leaks application build path'
    print('Pack consumer: typing, paste, resize, closed imports, ignored overrides, no loader symbols passed')
