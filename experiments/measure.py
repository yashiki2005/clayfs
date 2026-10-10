#!/usr/bin/env python3
"""重複排除と圧縮でどれだけ縮むかを、読み取りだけで見積もる。

  measure.py DIR [OUT.json]

各ファイルについて、中身のハッシュ (重複の検出)、64KiB ごとの zlib (APFS の透過圧縮に近い見積もり)、
全体の zstd -3 (restic の圧縮に近い見積もり) を取る。何も書き換えない。
"""
import collections, hashlib, json, os, sys, zlib
from multiprocessing import Pool
import compression.zstd as zstd

CHUNK = 64 * 1024
SKIP_DIRS = {'.Spotlight-V100', '.fseventsd', '.Trashes'}

def probe(path):
    try:
        st = os.lstat(path)
        h = hashlib.sha256(); zl = 0; zc = zstd.ZstdCompressor(level=3); zs = 0
        with open(path, 'rb') as f:
            while True:
                b = f.read(CHUNK)
                if not b: break
                h.update(b)
                zl += min(len(zlib.compress(b, 5)), len(b))
                zs += len(zc.compress(b))
        zs += len(zc.flush())
        return path, st.st_size, st.st_blocks * 512, h.hexdigest(), zl, min(zs, st.st_size)
    except OSError as e:
        return path, -1, 0, str(e), 0, 0

def main():
    root = os.path.realpath(sys.argv[1])
    files = []
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for fn in fns:
            p = os.path.join(dp, fn)
            if os.path.isfile(p) and not os.path.islink(p):
                files.append(p)
    with Pool(8) as pool:
        rows = pool.map(probe, files, chunksize=200)
    proj = collections.defaultdict(lambda: [0, 0, 0, 0, 0])   # files, bytes, zlib, zstd, dup bytes
    ext = collections.defaultdict(lambda: [0, 0, 0])
    seen = {}
    unreadable = []
    tot = [0, 0, 0, 0, 0]
    uniq_zlib = uniq_zstd = 0
    for path, size, alloc, h, zl, zs in rows:
        if size < 0:
            unreadable.append((os.path.relpath(path, root), h)); continue
        rel = os.path.relpath(path, root); top = rel.split(os.sep)[0]
        dup = size if (size, h) in seen and size > 0 else 0
        if not dup:
            seen[(size, h)] = rel
            # 4KiB 未満は 1 ブロックに収まるので、圧縮しても減らない
            uniq_zlib += zl if size > 4096 else size
            uniq_zstd += zs
        e = os.path.splitext(rel)[1].lower() or '(none)'
        for agg in (proj[top], tot):
            agg[0] += 1; agg[1] += size; agg[2] += zl if size > 4096 else size; agg[3] += zs; agg[4] += dup
        ext[e][0] += 1; ext[e][1] += size; ext[e][2] += zl if size > 4096 else size
    out = {
        'root': root, 'files': tot[0], 'bytes': tot[1],
        'duplicate_bytes': tot[4], 'after_dedup': tot[1] - tot[4],
        'zlib64k_all': tot[2], 'zlib64k_after_dedup': uniq_zlib, 'zstd3_after_dedup': uniq_zstd,
        'unreadable': unreadable[:50],
        'projects': {k: v for k, v in sorted(proj.items(), key=lambda kv: -kv[1][1])},
        'extensions': {k: v for k, v in sorted(ext.items(), key=lambda kv: -kv[1][1])[:25]},
    }
    json.dump(out, open(sys.argv[2] if len(sys.argv) > 2 else '/dev/stdout', 'w'), ensure_ascii=False, indent=1)

if __name__ == '__main__':
    main()
