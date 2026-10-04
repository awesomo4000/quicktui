#!/usr/bin/env python3
"""Run Zig tests without the stdio server protocol, which native UI output uses."""
import subprocess
import sys
try:
    result=subprocess.run(sys.argv[1:],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
    sys.stdout.buffer.write(result.stdout)
    raise SystemExit(result.returncode)
except subprocess.TimeoutExpired as error:
    sys.stdout.buffer.write(error.stdout or b'')
    print('Native tests exceeded 180 seconds',file=sys.stderr)
    raise SystemExit(1)
