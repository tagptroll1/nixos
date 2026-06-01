#!/usr/bin/env python3
"""Minimal Source 2 VPK directory parser — extracts file paths only."""
import struct, sys

def read_cstr(buf, i):
    end = buf.index(b'\0', i)
    return buf[i:end].decode('utf-8', 'replace'), end + 1

def parse(path, want_exts=None):
    with open(path, 'rb') as f:
        data = f.read()
    sig, ver, tree_size = struct.unpack_from('<III', data, 0)
    assert sig == 0x55AA1234, f"bad sig {sig:08x}"
    if ver == 1:
        i = 12
    elif ver == 2:
        i = 28
    else:
        raise SystemExit(f"unknown VPK version {ver}")
    tree_end = i + tree_size
    out = []
    while i < tree_end:
        ext, i = read_cstr(data, i)
        if not ext:
            break
        while True:
            d, i = read_cstr(data, i)
            if not d:
                break
            while True:
                fn, i = read_cstr(data, i)
                if not fn:
                    break
                # skip entry: CRC(4) PreloadBytes(2) ArchiveIndex(2) Offset(4) Length(4) Terminator(2)
                preload = struct.unpack_from('<H', data, i + 4)[0]
                i += 18 + preload
                full = (d + '/' + fn) if d != ' ' else fn
                if want_exts is None or ext in want_exts:
                    out.append(full + '.' + ext)
    return out

if __name__ == '__main__':
    vpk = sys.argv[1]
    exts = set(sys.argv[2].split(',')) if len(sys.argv) > 2 else None
    for p in parse(vpk, exts):
        print(p)
