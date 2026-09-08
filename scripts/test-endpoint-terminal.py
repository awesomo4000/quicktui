"""Disposable PTY: sustained native traffic alongside input, resize and quit."""
import os, pty, subprocess, sys, time, termios, fcntl, struct, signal
for iteration in range(8):
    master,slave=pty.openpty();saved=termios.tcgetattr(slave)
    process=subprocess.Popen([sys.argv[1]],stdin=slave,stdout=slave,stderr=slave)
    try:
        deadline=time.monotonic()+10
        while termios.tcgetattr(slave)==saved:
            if process.poll() is not None or time.monotonic()>deadline:raise AssertionError('host did not enter raw mode')
            time.sleep(.01)
        time.sleep(.03)
        fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',31,95,0,0))
        process.send_signal(signal.SIGWINCH)
        time.sleep(.03)
        os.write(master,b'x') # close transport while UI remains live
        time.sleep(.03)
        os.write(master,b'q')
        process.wait(timeout=5)
        if process.returncode:raise AssertionError(os.read(master,16384))
        restored=termios.tcgetattr(slave)
        # Darwin may set PENDIN when canonical mode is restored; it is kernel state.
        restored[3]&=~getattr(termios,'PENDIN',0);saved[3]&=~getattr(termios,'PENDIN',0)
        assert restored==saved, 'terminal modes not restored'
    finally:
        if process.poll() is None:process.kill();process.wait()
        os.close(master);os.close(slave)
print('Eight PTY flood/resize/input/disconnect/quit cycles passed.')
