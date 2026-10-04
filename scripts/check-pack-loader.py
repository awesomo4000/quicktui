#!/usr/bin/env python3
"""Inspect an unstripped pack-only C loader object, even on stripped releases."""
from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='quicktui-loader-symbols-') as directory:
    obj=Path(directory)/'loader.o'
    subprocess.run(['zig','cc','-DQT_SOURCE_LOADER=0','-DQUICKJS_LOADER_VERSION="2026-06-04"',
        '-I'+str(root/'vendor/quickjs'),'-I'+str(root/'src'),'-c',str(root/'src/module_loader.c'),
        '-o',str(obj)],check=True,timeout=60)
    symbols=subprocess.check_output(['nm',str(obj)],text=True)
    assert 'qt_modules_install' in symbols, 'No inspectable module loader symbols'
    for name in ['qt_fs_', 'qt_cache_', 'qt_hash_', 'quicktui_build_pack', 'host_read', 'install_realm']:
        assert name not in symbols, f'Pack-only object contains {name}'
print('Pack-only loader object: no filesystem/cache/build-tool entry points or references')
