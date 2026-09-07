"""Build original 16x16 game sprites in the termpaint palette. No image dependencies."""
import json, math, struct, zlib
from pathlib import Path
ROOT=Path(__file__).resolve().parent
PAL=['172038','f4f4e8','465074','8585a1','bfc7cf','ffffff','703040','b13e53','ef7d57','ffcd75','a7f070','38b764','257179','29366f','3b5dc9','41a6f6','73eff7','f4b5d5','de5b9e','8f3f95','5b2b82','402751','663931','8f563b','bf8c60','dfb580','e7d5b3','a6b7a5','597d75','334f5a','ff4038','ffe600']
ALPHABET='0123456789abcdefghijklmnopqrstuv.'
T=32
class Tile:
 def __init__(self):self.p=[T]*256
 def dot(self,x,y,c):
  if 0<=x<16 and 0<=y<16:self.p[y*16+x]=c
 def rect(self,x,y,w,h,c):
  for j in range(y,y+h):
   for i in range(x,x+w):self.dot(i,j,c)
 def line(self,x,y,xx,yy,c):
  n=max(abs(xx-x),abs(yy-y))
  for k in range(n+1):
   t=k/max(1,n);self.dot(round(x+(xx-x)*t),round(y+(yy-y)*t),c)
 def oval(self,x,y,w,h,c):
  for j in range(y,y+h):
   for i in range(x,x+w):
    if ((i-x+.5-w/2)/(w/2))**2+((j-y+.5-h/2)/(h/2))**2<=1:self.dot(i,j,c)
 def poly(self,points,c):
  for y in range(16):
   for x in range(16):
    inside=False
    for (a,b),(d,e) in zip(points,points[1:]+points[:1]):
     if (b>y+.5)!=(e>y+.5) and x+.5<(d-a)*(y+.5-b)/(e-b)+a:inside=not inside
    if inside:self.dot(x,y,c)
  for a,b in zip(points,points[1:]+points[:1]):self.line(*a,*b,c)

def hero(f):
 t=Tile();dy=-1 if f==2 else 0
 # Scarf trails behind the blue-armored adventurer.
 t.poly([(5,7+dy),(1,8+dy),(3,10+dy),(6,9+dy)],7);t.line(2,8+dy,5,8+dy,30)
 # Boots in distinct idle, walk, jump, attack and hurt stances.
 legs=[[(5,12,3,3),(9,12,3,3)],[(3,12,3,3),(10,11,3,3)],[(4,11,3,2),(10,11,3,2)],[(4,12,3,3),(10,12,4,3)],[(4,12,3,3),(9,12,3,3)]][f]
 for x,y,w,h in legs:t.rect(x,y,w,h,0);t.rect(x+1,y,w-1,1,23)
 t.rect(5,7+dy,7,6,0);t.rect(6,8+dy,5,4,14);t.rect(6,8+dy,2,3,15);t.dot(6,8+dy,16)
 t.rect(5,11+dy,7,1,22);t.dot(8,11+dy,9)
 # Hair silhouette and face, right-facing.
 t.rect(5,1+dy,6,6,0);t.rect(4,2+dy,8,3,0)
 t.rect(5,2+dy,6,3,23);t.rect(6,2+dy,4,1,9);t.rect(5,3+dy,2,2,24)
 t.rect(7,4+dy,4,3,25);t.rect(8,4+dy,3,2,9);t.dot(10,4+dy,0);t.dot(11,6+dy,0)
 t.rect(6,7+dy,5,1,30)
 # Guard hand and sword change pose.
 if f==3:
  t.rect(10,8,4,3,0);t.rect(11,8,2,2,9);t.line(13,7,13,11,9);t.line(14,8,15,8,5);t.line(14,9,15,9,4)
 elif f==4:
  t.rect(3,5,2,4,0);t.rect(3,5,2,2,9);t.line(10,4,11,5,0);t.dot(11,4,25)
 else:
  t.rect(11,8+dy,2,3,0);t.dot(11,9+dy,9);t.line(13,5+dy,13,10+dy,4);t.line(14,5+dy,14,8+dy,5);t.line(12,10+dy,14,10+dy,9)
 return t

def slime(f):
 t=Tile();x,y,w,h=[(2,6,12,9),(1,8,14,7),(4,2,9,12),(1,6,12,9),(2,9,12,6)][f]
 t.oval(x,y,w,h,0);t.oval(x+1,y+1,w-2,h-2,12);t.oval(x+1,y+1,w-2,h-3,11)
 t.oval(x+2,y+1,max(2,w//2),max(2,h//3),10);t.dot(x+3,y+2,1)
 ey=y+h//2
 if f==4:
  for ex in (x+w//3,x+2*w//3):t.line(ex-1,ey-1,ex+1,ey+1,0);t.line(ex-1,ey+1,ex+1,ey-1,0)
 else:
  for ex in (x+w//3,x+2*w//3):t.rect(ex,ey,2,2,0);t.dot(ex,ey,5)
  t.line(x+w//2,ey+3,x+w//2+1,ey+3,0)
 if f==3:t.oval(13,5,3,3,10);t.dot(14,5,1);t.rect(10,9,3,2,0)
 return t

def bat(f):
 t=Tile();bodyY=5 if f!=2 else 4
 wings=[[(1,3),(5,6),(5,11),(3,9),(1,10)],[(0,1),(5,5),(5,10),(2,6),(0,7)],[(0,8),(5,6),(5,11),(2,13),(1,11)],[(0,4),(5,6),(5,11),(2,9),(0,10)],[(2,8),(5,6),(5,11),(3,13)]][f]
 for mirror in (False,True):
  pts=[(15-x if mirror else x,y) for x,y in wings];t.poly(pts,0)
  pts2=[(15-x if mirror else x,y) for x,y in [(2,wings[0][1]+2),(4,7),(4,10)]];t.poly(pts2,19)
  t.line(11 if mirror else 4,7,14 if mirror else 1,wings[0][1]+1,18)
 t.rect(5,bodyY,6,8,0);t.rect(6,bodyY+1,4,6,20);t.rect(5,bodyY-2,2,3,0);t.rect(9,bodyY-2,2,3,0)
 t.dot(6,bodyY-1,18);t.dot(9,bodyY-1,18);t.rect(6,bodyY+1,4,2,19)
 for x in (6,9):t.dot(x,bodyY+3,9 if f!=4 else 0)
 t.rect(6,bodyY+5,4,1,0);t.dot(6,bodyY+5,5);t.dot(9,bodyY+5,5)
 if f==3:t.rect(7,bodyY+4,2,3,7);t.dot(7,bodyY+4,5)
 t.dot(6,bodyY+8,0);t.dot(9,bodyY+8,0)
 return t

def skeleton(f):
 t=Tile();dy=-1 if f==2 else 0
 # Limbs use outlined bones and joint pixels.
 legs=[[(6,11,5,14),(9,11,10,14)],[(6,11,3,14),(9,11,11,13)],[(6,11,4,12),(9,11,12,12)],[(6,11,4,14),(9,11,11,14)],[(6,11,6,14),(9,11,10,14)]][f]
 for x,y,xx,yy in legs:
  t.line(x-1,y,xx-1,yy,0);t.line(x+1,y,xx+1,yy,0);t.line(x,y,xx,yy,4);t.rect(xx-1,yy,3,1,0);t.dot(xx,yy,1)
 t.rect(5,7+dy,6,5,0);t.rect(7,7+dy,2,5,4)
 for y in [8+dy,10+dy]:t.line(6,y,9,y,1)
 t.rect(6,11+dy,4,1,4)
 t.oval(4,1+dy,8,7,0);t.oval(5,2+dy,6,5,4);t.rect(6,2+dy,4,2,1)
 t.rect(5,4+dy,2,2,0);t.rect(9,4+dy,2,2,0);t.dot(6,4+dy,30);t.dot(9,4+dy,30);t.dot(8,5+dy,0)
 t.rect(6,6+dy,4,1,1);t.dot(7,6+dy,0);t.dot(9,6+dy,0)
 if f==3:
  t.line(10,8,14,8,0);t.line(10,9,14,9,1);t.line(14,3,14,10,0);t.line(15,3,15,7,4);t.line(13,10,15,10,9)
 else:
  t.line(4,8+dy,3,11+dy,0);t.line(5,8+dy,4,11+dy,1)
  t.line(11,8+dy,12,10+dy,0);t.line(12,8+dy,13,10+dy,1)
 if f==4:t.line(5,3,6,4,0);t.dot(9,3,0)
 return t

sheet=[T]*(80*64);manifest={'tileWidth':16,'tileHeight':16,'columns':5,'rows':[]}
for row,(name,make) in enumerate([('adventurer',hero),('slime',slime),('bat',bat),('skeleton',skeleton)]):
 manifest['rows'].append({'character':name,'poses':['idle','walk-or-squash','jump-or-wing-down','attack','hurt'],'y':row*16})
 for col in range(5):
  tile=make(col)
  for y in range(16):sheet[(row*16+y)*80+col*16:(row*16+y)*80+col*16+16]=tile.p[y*16:y*16+16]
painting={'format':'termpaint','version':3,'width':80,'height':64,'pixels':''.join(ALPHABET[n] for n in sheet)}
(ROOT/'players-monsters.tpaint').write_text(json.dumps(painting,separators=(',',':')))
(ROOT/'players-monsters.json').write_text(json.dumps(manifest,indent=2)+'\n')
def png(path,w,h,rgba):
 def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
 scan=b''.join(b'\0'+rgba[y*w*4:(y+1)*w*4] for y in range(h))
 path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(scan))+chunk(b'IEND',b''))
rgba=b''.join(bytes.fromhex(PAL[n])+b'\xff' if n!=T else b'\0\0\0\0' for n in sheet)
png(ROOT/'players-monsters.png',80,64,rgba)
# Enlarged checkerboard preview, separate from the alpha-bearing source.
preview=bytearray()
for y in range(64):
 line=b''
 for x in range(80):
  n=sheet[y*80+x];c=bytes.fromhex(PAL[n]) if n!=T else bytes([70,75,87] if (x//4+y//4)%2 else [92,98,111]);line+=(c+b'\xff')*8
 preview.extend(line*8)
png(Path('/tmp/players-monsters-preview.png'),640,512,preview)
assert len(sheet)==5120 and all(0<=n<=32 for n in sheet)
print('Created 80x64 sheet: twenty 16x16 sprites, with alpha PNG and termpaint file.')
