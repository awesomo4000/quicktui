"""Edit a source file while `quicktui --run app.tsx --reload` runs, press Ctrl+R,
and check the new text renders and the typed draft survives the reload."""
import os, pty, select, shutil, subprocess, sys, tempfile, time, fcntl, termios, struct, pathlib
root = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parent.parent; exe = pathlib.Path(os.environ.get("QT_EXE", root / "zig-out/bin/quicktui"))
with tempfile.TemporaryDirectory(prefix="qt-hot-") as d:
    app = pathlib.Path(d) / "app.tsx"
    shutil.copy(root / "examples/reload-consumer/app.tsx", app)
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    env = dict(os.environ, QUICKTUI_CACHE=str(pathlib.Path(d) / "cache"))
    p = subprocess.Popen([str(exe), "--run", str(app), "--reload"], stdin=slave, stdout=slave, stderr=slave, env=env)
    out = bytearray()
    def until(needle, timeout=60):
        end = time.monotonic() + timeout
        while needle not in out:
            if time.monotonic() > end: raise AssertionError((needle, bytes(out[-600:])))
            if select.select([master], [], [], .1)[0]: out.extend(os.read(master, 65536))
    try:
        t = time.monotonic(); until(b"Independent reload app"); print(f"first frame {time.monotonic()-t:.2f}s")
        os.write(master, b"\x1b[200~hello\x1b[201~"); until(b"hello")
        app.write_text(app.read_text().replace("Independent reload app", "Edited on disk app"))
        out.clear(); t = time.monotonic(); os.write(master, b"\x12")
        until(b"Edited on disk app"); print(f"reload with edit {time.monotonic()-t:.2f}s")
        until(b"hello"); print("draft survived reload")
        os.write(master, b"\x03")
        end = time.monotonic() + 10
        while p.poll() is None and time.monotonic() < end:
            if select.select([master], [], [], .1)[0]: os.read(master, 65536)
        print("exit", p.returncode)
        assert p.returncode == 0
    finally:
        if p.poll() is None:
            p.kill()
            p.wait()
        os.close(master)
        os.close(slave)
