"""Build a real consumer outside the checkout; all fixtures are disposable."""
import sys
import pathlib, shutil, subprocess, tempfile, json, os, pty, select, time, signal, termios, fcntl, struct
reload_test="--reload" in sys.argv
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='quicktui-consumer-') as directory:
    app=pathlib.Path(directory).resolve()
    for name in ('app.tsx','main.zig','build.zig'):
        shutil.copy(root/('examples/reload-consumer' if reload_test else 'examples/consumer')/name,app/name)
    (app/'build.zig.zon').write_text('.{ .name = .quicktui_consumer, .version = "0.0.0", .dependencies = .{ .quicktui = .{ .path = '+json.dumps(os.path.relpath(root,app))+' } }, .paths = .{""} }')
    subprocess.run(['bun',str(root/'scripts/bundle-app.ts'),'app.tsx','app.js'],cwd=app,check=True)
    command=['zig','build','--cache-dir',str(app/'.zig-cache'),'-Doptimize=ReleaseSmall','--global-cache-dir',str(root/'.zig-cache/global')]
    result=subprocess.run(command,cwd=app,capture_output=True,text=True)
    # Zig derives a package fingerprint from its name; record the suggestion only
    # in this disposable manifest, never by editing the checked-in project.
    if result.returncode and 'suggested value' in result.stderr:
        import re
        value=re.search(r'suggested value: (0x[0-9a-f]+)',result.stderr)
        if value:
            p=app/'build.zig.zon';p.write_text(p.read_text().replace('.version =', '.fingerprint = '+value[1]+', .version ='))
            result=subprocess.run(command,cwd=app,capture_output=True,text=True)
    if result.returncode: raise RuntimeError(result.stderr)
    executable=app/'zig-out/bin/consumer'
    if not reload_test: subprocess.run([str(executable),'--self-test'],check=True,timeout=30)
    master,slave=pty.openpty();saved=termios.tcgetattr(slave)
    fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',24,80,0,0))
    process=subprocess.Popen([str(executable)],stdin=slave,stdout=slave,stderr=slave,cwd=app)
    output=bytearray()
    def read_until(needle):
        deadline=time.monotonic()+10
        while needle not in output:
            if time.monotonic()>deadline:raise AssertionError(('missing terminal output',needle,bytes(output[-1000:])))
            if select.select([master],[],[],.1)[0]:output.extend(os.read(master,65536))
    try:
        read_until(b'Independent reload app' if reload_test else b'Independent app')
        os.write(master,b'q')
        os.write(master,b'\x1b[200~hello\nworld\x1b[201~')
        read_until(b'hello')
        assert process.poll() is None, 'q must not exit a consumer'
        if reload_test:
            output.clear()
            os.write(master,b'\x12')
            # The renderer emits changed spans, not necessarily a whole line.
            read_until(b'qhello')
            read_until(b'world')
            for sequence in (b'\x1b[?1049l',b'\x1b[?1049h',b'\x1b[2J'):
                assert sequence not in output, 'reload reset the terminal'

        fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',30,96,0,0));process.send_signal(signal.SIGWINCH)
        os.write(master,b'\x03')
        deadline=time.monotonic()+10
        while process.poll() is None:
            if time.monotonic()>deadline:raise AssertionError('quit timed out')
            if select.select([master],[],[],.1)[0]:output.extend(os.read(master,65536))
        assert process.returncode==0
        restored=termios.tcgetattr(slave)
        # Darwin may set PENDIN when canonical mode is restored; it is kernel state.
        restored[3]&=~getattr(termios,'PENDIN',0);saved[3]&=~getattr(termios,'PENDIN',0)
        assert restored==saved, 'terminal modes not restored'
    finally:
        if process.poll() is None:process.kill();process.wait()
        os.close(master);os.close(slave)
    print('External reload consumer: public API, draft restoration, and PTY cleanup passed.' if reload_test else 'External consumer: build, headless input/paste/resize, and real PTY quit/cleanup passed.')
