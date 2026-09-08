"""Verify replacement keeps terminal modes and screen continuity in a disposable PTY."""
import errno, fcntl, os, select, struct, subprocess, sys, termios, time
from pathlib import Path
master, slave = os.openpty()
process = None
try:
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 32, 110, 0, 0))
    original = termios.tcgetattr(slave)
    env = {k:v for k,v in os.environ.items() if k not in ("TMUX", "STY", "ZELLIJ")}
    process = subprocess.Popen([str(Path(sys.argv[1]).resolve()), "--reload"], stdin=slave,
        stdout=slave, stderr=slave, env={**env, "TERM":"xterm-256color"}, start_new_session=True)
    def collect(seconds):
        data = bytearray()
        until = time.monotonic()+seconds
        while time.monotonic()<until:
            if select.select([master], [], [], .03)[0]:
                try: data.extend(os.read(master, 65536))
                except OSError as e:
                    if e.errno != errno.EIO: raise
                    break
        return bytes(data)
    initial = collect(1.5)
    assert b"Fresh runtime" in initial, initial[-1500:]
    assert b"\x1b[?1049h" in initial
    os.write(master,b"  uu")
    collect(.3)
    for key in (b"r",b"r",b"b",b"r"):
        os.write(master,key)
        changed=collect(1.0)
        assert process.poll() is None, changed[-1500:]
        assert changed, "Replacement did not produce a frame"
        for forbidden in (b"\x1b[?1049l",b"\x1b[?1049h",b"\x1b[2J",b"\x1b[3J",b"\x1bc",b"\x1b[?1003l"):
            assert forbidden not in changed, (forbidden,changed[-1500:])
        if key==b"b": assert b"Replacement failed" in changed, changed[-2000:]
    os.write(master,b"q")
    final=collect(1)
    process.wait(timeout=3)
    assert process.returncode==0,final[-1500:]
    assert b"\x1b[?1049l" in final
    restored=termios.tcgetattr(slave)
    for attrs in (original,restored): attrs[3]&=~getattr(termios,"PENDIN",0)
    assert restored==original
    print("PASS fresh-runtime replacement, broken-bundle recovery, no screen reset, and final terminal restoration")
finally:
    if process is not None and process.poll() is None: process.kill();process.wait()
    os.close(master);os.close(slave)
