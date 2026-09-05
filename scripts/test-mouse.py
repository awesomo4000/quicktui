"""Check mouse reporting and cleanup using disposable child PTYs."""
import errno, fcntl, os, select, signal, struct, subprocess, sys, termios, time
from pathlib import Path
exe=str(Path(sys.argv[1]).resolve())
example=sys.argv[2] if len(sys.argv)>2 else '--mouse'
for action in [b'\x1b' if example=='--gallery' else b'q', signal.SIGTERM]:
    master,slave=os.openpty()
    process=None
    try:
        fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',30,96,0,0))
        original=termios.tcgetattr(slave)
        env={k:v for k,v in os.environ.items() if k not in ['TMUX','STY','ZELLIJ']}
        process=subprocess.Popen([exe,example],stdin=slave,stdout=slave,stderr=slave,env={**env,'TERM':'xterm-256color'},start_new_session=True)
        output=bytearray()
        def receive(predicate):
            deadline=time.monotonic()+10
            while time.monotonic()<deadline:
                if select.select([master],[],[],0.05)[0]:
                    try: output.extend(os.read(master,65536))
                    except OSError as e:
                        if e.errno!=errno.EIO: raise
                if predicate(): return
            raise AssertionError(repr(output[-1500:]))
        receive(lambda:({'--gallery':b'Widget gallery','--messages':b'Native messages'}.get(example,b'Wheel value:')) in output)
        assert b'\x1b[?1003h' in output and b'\x1b[?1006h' in output
        if example=='--messages':
            # Pause the UI timer, then require a worker reply to wake the host.
            os.write(master,b'ps')
            receive(lambda:b'done' in output)
            os.write(master,b'b')  # Quit with native work pending.
        if isinstance(action,bytes):os.write(master,action)
        else:process.send_signal(action)
        receive(lambda:process.poll() is not None)
        assert process.returncode==0,output[-1500:]
        assert b'\x1b[?1003l' in output and b'\x1b[?1006l' in output
        restored=termios.tcgetattr(slave)
        for attrs in [restored,original]:attrs[3]&=~getattr(termios,'PENDIN',0)
        assert restored==original
        print(f'PASS {example} reporting and terminal restoration: {action!r}')
    finally:
        if process and process.poll() is None:process.kill();process.wait()
        os.close(master);os.close(slave)
