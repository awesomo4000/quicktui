#!/usr/bin/env python3
"""Maintenance-only extraction of selected unchanged Bun fixture objects. Requires Bun."""
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent / 'tests/reference/bun'
revision = '9bd19c98eacc01530a4e7609bc427abffa87d77e'
selected = {
    'esbuild/packagejson.test.ts': [
        'packagejson/ExportsImportOverRequire',
        'packagejson/ExportsDefaultOverImportAndRequire',
        'packagejson/ExportsBrowser',
        'packagejson/ExportsRequireOverImport',
        'packagejson/ExportsErrorPackagePathNotExported',
        'packagejson/ExportsErrorModuleNotFound',
        'packagejson/ExportsErrorUnsupportedDirectoryImport',
        'packagejson/ExportsNoConditionsMatch',
    ],
    'esbuild/default.test.ts': [
        'default/DefineInfiniteLoopESBuildIssue2407',
        'default/DefineOptionalChain',
    ],
}
fixtures = []
with tempfile.TemporaryDirectory(prefix='quicktui-reference-extract-', dir='/tmp') as directory:
    script = Path(directory)/'extract.js'
    for file, names in selected.items():
        source = (root/'upstream'/file).read_text()
        for name in names:
            marker = '  itBundled(' + json.dumps(name) + ', '
            assert source.count(marker) == 1, name
            start = source.index(marker) + len(marker)
            end = source.index('\n  });', start) + len('\n  }')
            # Pinned selected cases contain self-contained data objects. The
            # full upstream test module and its test runner are never executed.
            script.write_text('console.log(JSON.stringify((' + source[start:end] + ')));')
            data = json.loads(subprocess.check_output(['bun', script], text=True))
            fixtures.append({'name': name, 'source': file, 'case': data})
manifest = {'revision': revision, 'sha256': {
    str(file.relative_to(root/'upstream')): hashlib.sha256(file.read_bytes()).hexdigest()
    for file in sorted((root/'upstream').rglob('*.ts'))}, 'fixtures': fixtures}
(root/'fixtures.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Extracted {len(fixtures)} reference cases')
