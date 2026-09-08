"""Exercise disk loading and watching in a disposable PTY and source directory."""
import errno, fcntl, os, select, struct, subprocess, sys, tempfile, termios, time
from pathlib import Path
exe = str(Path(sys.argv[1]).resolve())
def script(marker):
    return 'api.register("demo", {title: "'+marker+'", render: () => h("text", {}, "'+marker+'")});\n'
with tempfile.TemporaryDirectory(prefix="quicktui-live-", dir="/tmp") as directory:
    root = Path(directory)
    (root / "counter.js").write_text(script("111111111"))
    (root / "clock.js").write_text('api.register("extra",{title:"333333333",render:()=>h("text",{},"extra")});')
    master, slave = os.openpty()
    process = None
    try:
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 36, 110, 0, 0))
        original = termios.tcgetattr(slave)
        env = {k:v for k,v in os.environ.items() if k not in ("TMUX","STY","ZELLIJ")}
        process = subprocess.Popen([exe, "--live", directory], stdin=slave, stdout=slave,
            stderr=slave, env={**env, "TERM":"xterm-256color"}, start_new_session=True)
        output = bytearray()
        def wait_for(token):
            start = time.monotonic()
            while time.monotonic() - start < 8:
                if token in output: return
                if select.select([master], [], [], .05)[0]:
                    try: output.extend(os.read(master, 65536))
                    except OSError as e:
                        if e.errno != errno.EIO: raise
                if process.poll() is not None: break
            raise AssertionError((token, bytes(output[-2500:])))
        wait_for(b"Live components")
        os.write(master, b"1")
        wait_for(b"111111111")
        os.write(master, b"2")
        wait_for(b"333333333")
        os.write(master, b"1w")
        wait_for(b"ON")
        # No key input after this edit: the watcher must deliver new code itself.
        temporary = root / "replacement.js"
        temporary.write_text(script("222222222"))
        temporary.replace(root / "counter.js")
        wait_for(b"222222222")
        (root / "counter.js").write_text("const = ;")
        wait_for(b"Load failed")
        temporary.write_text(script("444444444"))
        temporary.replace(root / "counter.js")
        wait_for(b"444444444")
        os.write(master, b"q")
        process.wait(timeout=5)
        assert process.returncode == 0, output[-2500:]
        restored = termios.tcgetattr(slave)
        # PENDIN is macOS kernel bookkeeping, not an application terminal mode.
        for attrs in (restored, original):
            attrs[3] &= ~getattr(termios, "PENDIN", 0)
        assert restored == original
        print("PASS live disk load, additive script, atomic-save watch, syntax recovery, and terminal restoration")
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        os.close(slave)
