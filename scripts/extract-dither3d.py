"""Extract the pinned Unity R8 texture and one-row PNG ramp without build dependencies."""
from pathlib import Path
import re, struct, zlib
source = Path(__file__).resolve().parents[1]
vendor = source / "vendor/dither3d"
output = source / "src/examples/dither3d"
data = bytes.fromhex(re.search(r"_typelessdata: ([0-9a-f]+)", (vendor / "Dither3D_4x4.asset").read_text())[1])
assert len(data) == 64 * 64 * 16
(output / "pattern.r8").write_bytes(data)
png = (vendor / "Dither3D_4x4_Ramp.png").read_bytes()
pos, compressed = 8, b""
while pos < len(png):
    size = struct.unpack(">I", png[pos:pos+4])[0]
    kind, chunk = png[pos+4:pos+8], png[pos+8:pos+8+size]
    if kind == b"IHDR":
        assert struct.unpack(">IIBBBBB", chunk) == (64, 1, 8, 0, 0, 0, 0)
    if kind == b"IDAT": compressed += chunk
    pos += size + 12
raw = zlib.decompress(compressed)
row = bytearray(raw[1:])
assert len(row) == 64 and raw[0] in (0, 1)
if raw[0] == 1:
    for i in range(1, 64): row[i] = (row[i] + row[i-1]) & 255
(output / "ramp.r8").write_bytes(row)
