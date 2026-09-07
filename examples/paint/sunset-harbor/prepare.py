"""Prepare original neon city artwork for 256x192 palette cycling using macOS sips."""
import struct,json,math,zlib,subprocess,tempfile
from pathlib import Path
from collections import Counter
root=Path(__file__).resolve().parent
with tempfile.TemporaryDirectory(prefix='termpaint-water-') as tmp:
 bmp=Path(tmp)/'source.bmp'
 subprocess.run(['sips','-z','192','256','-s','format','bmp',str(root/'source.png'),'--out',str(bmp)],check=True,stdout=subprocess.DEVNULL)
 data=bmp.read_bytes()
off=struct.unpack_from('<I',data,10)[0];w,h=struct.unpack_from('<ii',data,18);bits=struct.unpack_from('<H',data,28)[0];stride=((w*bits+31)//32)*4
assert (w,abs(h))==(256,192) and bits in (24,32)
pixels=[]
for y in range(192):
 for x in range(w):
  i=off+(191-y if h>0 else y)*stride+x*(bits//8);b,g,r=data[i:i+3];pixels.append((r,g,b))
def water(c,x,y):
 r,g,b=c
 cyan=b>100 and g>r*1.35 and b>r*1.35
 pink=r>110 and b>90 and r>g*1.6 and b>g*1.25
 return (cyan or pink) and y>119
mask=[water(c,i%256,i//256) for i,c in enumerate(pixels)]
# Weighted median cut: sixteen warm scenery entries, eight static water entries.
def quantize(values,n):
 hist=Counter(tuple((c//8)*8+4 for c in p) for p in values);boxes=[list(hist)]
 while len(boxes)<n:
  def score(box):return max(max(c[a] for c in box)-min(c[a] for c in box) for a in range(3))*math.sqrt(sum(hist[c] for c in box)) if len(box)>1 else 0
  box=max(boxes,key=score);boxes.remove(box)
  axis=max(range(3),key=lambda a:max(c[a] for c in box)-min(c[a] for c in box));box.sort(key=lambda c:c[axis]);total=sum(hist[c] for c in box);acc=0;split=1
  for j,c in enumerate(box[:-1]):
   acc+=hist[c]
   if acc>=total/2:split=j+1;break
  boxes.extend([box[:split],box[split:]])
 return [tuple(round(sum(c[a]*hist[c] for c in box)/sum(hist[c] for c in box)) for a in range(3)) for box in boxes]
base=quantize(pixels,24)
ramp=['7850a8','b168ce','ed85d3','d9b9f0','94def7','53cae6','72a4df','8b71bf'];colors=base+[tuple(bytes.fromhex(c)) for c in ramp]
indices=[]
for i,(c,m) in enumerate(zip(pixels,mask)):
 x,y=i%256,i//256;lum=sum(c)/3
 # Flow phase is a spatial field. A diagonal ribbon falls downward; rings spread in the pool.
 if m and ((x*13+y*7)%11<6):
  if y>119:phase=y*.48+1.2*math.sin(x*.13)+.4*math.sin(y*.24)
  else:phase=x*.10+y*.07
  indices.append(24+int(phase)%8)
 else:
  indices.append(min(range(24),key=lambda k:sum((a-b)**2 for a,b in zip(c,colors[k]))))
alpha='0123456789abcdefghijklmnopqrstuv.'
obj={'format':'termpaint','version':3,'width':256,'height':192,'palette':['#%02x%02x%02x'%c for c in colors],'cycle':{'start':24,'end':31,'stepMs':190,'direction':1,'blend':True},'pixels':''.join(alpha[n] for n in indices)}
(root/'sunset-harbor.tpaint').write_text(json.dumps(obj,separators=(',',':')))
def png(path,scale=1,phase=0):
 def chunk(k,d):return struct.pack('>I',len(d))+k+d+struct.pack('>I',zlib.crc32(k+d)&0xffffffff)
 display=colors[:]
 for k in range(8):display[24+k]=colors[24+(k-phase)%8]
 rows=[]
 for y in range(192):
  row=b''.join(bytes(display[k])*scale for k in indices[y*256:(y+1)*256]);rows.extend([b'\0'+row]*scale)
 path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',256*scale,192*scale,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(b''.join(rows)))+chunk(b'IEND',b''))
png(root/'sunset-harbor.png');png(Path('/tmp/sunset-harbor-preview.png'),3)
print('Neon mask pixels:',sum(mask),'animated:',sum(n>=24 for n in indices),'file bytes:',(root/'sunset-harbor.tpaint').stat().st_size)
