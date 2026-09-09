"""Injected terminal protocol checks; this does NOT verify physical key-up forwarding."""
import fcntl,os,select,signal,struct,subprocess,sys,termios,time
from pathlib import Path
exe=str(Path(sys.argv[1]).resolve())
for supported in (False,True):
 master,slave=os.openpty();process=None
 try:
  fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',38,110,0,0));saved=termios.tcgetattr(slave)
  env={k:v for k,v in os.environ.items() if k not in ('TMUX','STY','ZELLIJ','TERM_PROGRAM','TERM_PROGRAM_VERSION')}
  process=subprocess.Popen([exe,'--keyboard'],stdin=slave,stdout=slave,stderr=slave,env={**env,'TERM':'xterm-256color'},start_new_session=True)
  def collect(duration=.5):
   result=bytearray();until=time.monotonic()+duration
   while time.monotonic()<until:
    if select.select([master],[],[],.02)[0]:result.extend(os.read(master,65536))
   return bytes(result)
  output=collect(1);assert b'Keyboard laboratory' in output
  if supported:
   os.write(master,b'\x1bP>|kitty(0.40.1)\x1b\\\x1b[?1004;2$y');output+=collect()
   assert b'\x1b[>31u' in output,output[-2000:]
   assert b'\x1b[?1004h' in output
   os.write(master,b'\x1b[100;1u\x1b[32;1u\x1b[32;1:2u\x1b[32;1:3u\x1b[100;2:3u')
   events=collect();output+=events;assert b'release' in events
   os.write(master,b'\x1b[O');output+=collect();process.send_signal(signal.SIGCONT);output+=collect()
  else:
   os.write(master,b'a');output+=collect();assert b'\x1b[>31u' not in output
  os.write(master,b'\x03');output+=collect();process.wait(timeout=3);assert process.returncode==0
  if supported:
   assert output.count(b'\x1b[>31u')==1, 'unbalanced keyboard pushes'
   assert b'\x1b[<u' in output or b'\x1b[<1u' in output, 'missing keyboard pop'
  restored=termios.tcgetattr(slave)
  for attrs in (saved,restored):attrs[3]&=~getattr(termios,'PENDIN',0)
  assert saved==restored
  print('PASS injected keyboard PTY, supported='+str(supported))
 finally:
  if process is not None and process.poll() is None:process.kill();process.wait()
  os.close(master);os.close(slave)
