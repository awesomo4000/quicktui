"""Exercise only disposable PTYs and child processes owned by this test."""
import errno
import fcntl
import os
from pathlib import Path
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time

executable = str(Path(sys.argv[1] if len(sys.argv) > 1 else "zig-out/bin/quicktui").resolve())


def receive(master, output, predicate, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate(output):
            return
        if select.select([master], [], [], 0.1)[0]:
            try:
                data = os.read(master, 65536)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not data:
                break
            output.extend(data)
    assert predicate(output), f"Timed out waiting for terminal output: {bytes(output[-1500:])!r}"


for exit_action in [b"q", b"\x03", signal.SIGTERM, signal.SIGHUP, signal.SIGINT]:
    master, slave = os.openpty()
    process = None
    try:
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
        original = termios.tcgetattr(slave)
        process = subprocess.Popen(
            [executable], stdin=slave, stdout=slave, stderr=slave,
            env={**os.environ, "TERM": "xterm-256color"}, start_new_session=True,
        )
        output = bytearray()
        receive(master, output, lambda data: b"Count: 0" in data)
        assert not termios.tcgetattr(slave)[3] & termios.ICANON, "Application did not enter raw mode"
        os.write(master, b"  \x1b[")
        time.sleep(0.01)
        os.write(master, b"A")
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 20, 64, 0, 0))
        process.send_signal(signal.SIGWINCH)
        # The renderer can emit only changed cells, so the width may arrive
        # separately from the unchanged "Terminal " prefix.
        receive(master, output, lambda data: b"m64\x1b" in data or b"Terminal 64" in data)
        if isinstance(exit_action, bytes):
            os.write(master, exit_action)
        else:
            process.send_signal(exit_action)
        receive(master, output, lambda data: process.poll() is not None)
        assert process.returncode == 0, f"Exit {exit_action!r}: status {process.returncode}"
        restored = termios.tcgetattr(slave)
        # macOS marks pending input for reprocessing when canonical mode returns.
        # PENDIN is kernel state, not a mode the application failed to restore.
        restored[3] &= ~getattr(termios, "PENDIN", 0)
        original[3] &= ~getattr(termios, "PENDIN", 0)
        assert restored == original, f"Terminal modes not restored for {exit_action!r}"
        # Drain bytes emitted during cleanup and verify the alternate screen ends.
        while select.select([master], [], [], 0)[0]:
            chunk = os.read(master, 65536)
            if not chunk:
                break
            output.extend(chunk)
        assert b"\x1b[?1049l" in output, "Alternate screen was not restored"
        assert b"\x1b[?25h" in output, "Cursor visibility was not restored"
        print(f"PASS terminal resize and restoration: {exit_action!r}")
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)

# Terminal capabilities must not be inferred from an application name or from
# an unrelated reply. Exercise raw and tmux-wrapped probes in isolated PTYs.
for in_tmux, response in [(False, b"OK"), (True, b"OK"), (True, b"ERROR:unsupported"), (True, None)]:
    master, slave = os.openpty()
    process = None
    try:
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 33, 80, 0, 0))
        environment = {key: value for key, value in os.environ.items() if key not in {"TMUX", "STY", "ZELLIJ", "ZELLIJ_SESSION_NAME", "ZELLIJ_PANE_ID", "TERM_PROGRAM"}}
        environment["TERM"] = "xterm-256color"
        if in_tmux:
            environment["TMUX"] = "/tmp/quicktui-test-tmux/default,1,0"
        process = subprocess.Popen([executable], stdin=slave, stdout=slave, stderr=slave, env=environment, start_new_session=True)
        output = bytearray()
        receive(master, output, lambda data: b"Count: 0" in data)
        query = b"\x1b_Gi=31337,s=1,v=1,a=q,t=d,f=24;AAAA\x1b\\"
        wrapped = b"\x1bPtmux;" + query.replace(b"\x1b", b"\x1b\x1b") + b"\x1b\\"
        assert (wrapped if in_tmux else query) in output, "Incorrect graphics probe framing"
        if in_tmux:
            assert query not in output.replace(wrapped, b""), "Unwrapped graphics probe leaked through tmux"
        assert b"a=t," not in output, "Image transmitted before graphics confirmation"
        os.write(master, b"\x1b_Gi=999;OK\x1b\\")
        if response is not None:
            os.write(master, b"\x1b_Gi=31337;")
            time.sleep(0.01)
            os.write(master, response + b"\x1b\\")
        if response == b"OK":
            transmit = b"\x1bPtmux;\x1b\x1b_Ga=t," if in_tmux else b"\x1b_Ga=t,"
            receive(master, output, lambda data: transmit in data)
            receive(master, output, lambda data: b"a=p," in data and b",z=" in data)
            placement = re.search(rb"a=p,[^\x1b]*,z=(-?\d+)", output)
            assert placement and int(placement[1]) >= -1073741824, "Picture is hidden behind opaque cell backgrounds"
            if in_tmux:
                receive(master, output, lambda data: "\U0010eeee".encode() in data)
                assert b",U=1" in output, "tmux requires a virtual image placement"
                placement = re.search(rb"a=p,[^\x1b]*,z=(-?\d+)[^\x1b]*,U=1", output)
                assert placement and int(placement[1]) >= -1073741824, "Picture is hidden behind opaque cell backgrounds"
        else:
            receive(master, output, lambda data: b"fallback" in data)
            assert b"a=t," not in output, "Image transmitted after failed or missing probe"
        os.write(master, b"q")
        receive(master, output, lambda data: process.poll() is not None)
        assert process.returncode == 0
        print(f"PASS graphics probe, confirmation, and fallback: tmux={in_tmux}, reply={response!r}")
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)

if len(sys.argv) > 2:
    master, slave = os.openpty()
    process = None
    try:
        original = termios.tcgetattr(slave)
        process = subprocess.Popen(
            [str(Path(sys.argv[2]).resolve())], stdin=slave, stdout=slave, stderr=slave,
            env={**os.environ, "TERM": "xterm-256color"}, start_new_session=True,
        )
        output = bytearray()
        receive(master, output, lambda data: process.poll() is not None)
        assert process.returncode == 0, "Failure fixture did not observe the expected exception"
        restored = termios.tcgetattr(slave)
        restored[3] &= ~getattr(termios, "PENDIN", 0)
        original[3] &= ~getattr(termios, "PENDIN", 0)
        assert restored == original, "JavaScript exception left terminal modes changed"
        assert b"intentional terminal test failure" in output
        assert output.index(b"\x1b[?1049l") < output.index(b"intentional terminal test failure"), "Error printed before terminal restoration"
        print("PASS terminal restoration and deferred diagnostics after JavaScript failure")
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)
