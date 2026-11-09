#!/usr/bin/env python3
"""差分の読み取り (parse_dump) のテスト。btrfs を用意しなくても動く (receive --dump の出力を手で書いて与える)。

実出力 (btrfs-progs 6.17、Pi 5) の形:

    At subvol ./c-...
    snapshot ./c-... parent_uuid=...        ← -p を付けたとき (親は「親 subvolume」として付くだけ。
                                               親のファイルの mkfile は並ばない)
    mkdir    ./c-.../o25045-2057-0          ← 新規は一時名で作り
    rename   ./c-.../o25045-2057-0 dest=./c-.../revtest
    chown / chmod / utimes ./c-.../revtest  ← メタデータは「実名」で来る
    mkfile   ./c-.../name.o1-2-0
    write    ./c-.../name.o1-2-0            ← 中身は一時名で書き
    rename   ./c-.../name.o1-2-0 dest=./c-.../name
    utimes   ./c-.../name

一時名を捨てると変更が消え、実名のメタデータで上書きすると新規が「変更」になる。その取り違えを確かめる。
「親にあるか」は、親のディレクトリにその名前があるかで判定する (rename で付いた名前が新規かどうか)。

使い方: python3 linux/test_parse_dump.py [clayfs_btrfs のパス]  (既定は同ディレクトリの clayfs_btrfs)
"""
import importlib.machinery, importlib.util, os, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'clayfs_btrfs')
loader = importlib.machinery.SourceFileLoader('cbt', path)
spec = importlib.util.spec_from_loader('cbt', loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)

old_dir = tempfile.mkdtemp(); new_dir = tempfile.mkdtemp()
fails = 0


def put(root, rel, content):
    p = os.path.join(root, rel)
    if os.path.isdir(os.path.dirname(p)):
        pass
    else:
        os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w') as f:
        f.write(content)


def check(name, got, want):
    global fails
    ok = got == want
    if not ok:
        fails += 1
    print(('ok   ' if ok else 'FAIL ') + name)
    if not ok:
        print('   got:', got, '\n   want:', want)


def run(dump):
    """親 (old_dir) と現状 (new_dir) の中身から、名前ごとの変化を判定する。"""
    def mtime_changed(rel):
        try:
            return os.lstat(os.path.join(old_dir, rel)).st_mtime_ns != os.lstat(os.path.join(new_dir, rel)).st_mtime_ns
        except OSError:
            return True

    def content_changed(rel):
        a, b = os.path.join(old_dir, rel), os.path.join(new_dir, rel)
        try:
            return open(a, 'rb').read() != open(b, 'rb').read()
        except OSError:
            return True

    def existed(rel):
        return os.path.lexists(os.path.join(old_dir, rel))

    return m.parse_dump(dump, mtime_changed, content_changed, existed)


# 実機 (Pi 5, btrfs-progs 6.17) で取った、そのままの出力。新規ディレクトリ 2 つを作ったときのもの。
REAL_DUMP = """At subvol /srv/clayfs/store/layers/c-20261109-210000
snapshot        ./c-20261109-210000             uuid=29c3b2b3-2277-4d49-a1c5-f9bf5c9cd87e transid=2065 parent_uuid=d713013e-91f6-054d-91a2-a6fe1199793b parent_transid=1116
mkdir           ./c-20261109-210000/o25045-2057-0
rename          ./c-20261109-210000/o25045-2057-0 dest=./c-20261109-210000/revtest
chown           ./c-20261109-210000/revtest     gid=1000 uid=1000
chmod           ./c-20261109-210000/revtest     mode=775
mkdir           ./c-20261109-210000/o25046-2062-0
rename          ./c-20261109-210000/o25046-2062-0 dest=./c-20261109-210000/exp
chown           ./c-20261109-210000/exp         gid=1000 uid=1000
chmod           ./c-20261109-210000/exp         mode=775
utimes          ./c-20261109-210000/exp         atime=2026-11-09T20:59:30+0900 mtime=2026-11-09T20:58:20+0900 ctime=2026-11-09T20:58:20+0900
utimes          ./c-20261109-210000/            atime=2026-11-09T20:59:20+0900 mtime=2026-11-09T20:59:10+0900 ctime=2026-11-09T20:59:10+0900
utimes          ./c-20261109-210000/revtest     atime=2026-11-09T20:59:20+0900 mtime=2026-11-09T20:57:35+0900 ctime=2026-11-09T20:57:35+0900
"""
check('REAL DUMP: 新規ディレクトリ 2 つは A (実名の chown/chmod/utimes で M にしない)',
      run(REAL_DUMP), [('A', 'exp'), ('A', 'revtest')])

# 実機 (Pi 5, btrfs-progs 6.17) で取った、既存ファイル f.txt を "a" -> "b" に変えたときの出力そのもの。
# 中身の変更は「実名」で update_extent が出る (一時名を使わない)。
REAL_DUMP_CONTENT = """At subvol /srv/clayfs/work/dumpchk.s2
snapshot        ./dumpchk.s2                    uuid=0fadeb6c-38b6-a945-bfb9-9c71b73d59c4 transid=2078 parent_uuid=823d2f11-27b3-774d-a3df-46438284f516 parent_transid=2077
update_extent   ./dumpchk.s2/f.txt              offset=0 len=2
utimes          ./dumpchk.s2/f.txt              atime=2026-11-09T21:04:54+0900 mtime=2026-11-09T21:04:54+0900 ctime=2026-11-09T21:04:54+0900
"""
put(old_dir, 'f.txt', 'a\n'); put(new_dir, 'f.txt', 'b\n')
check('REAL DUMP (中身の変更): 実名の update_extent で M',
      run(REAL_DUMP_CONTENT), [('M', 'f.txt')])

# 実機の形のまま、中身も mtime も同じ (書き直しただけ) なら変更なし
put(old_dir, 'f.txt', 'same'); put(new_dir, 'f.txt', 'same')
st = os.lstat(os.path.join(old_dir, 'f.txt'))
os.utime(os.path.join(new_dir, 'f.txt'), ns=(st.st_atime_ns, st.st_mtime_ns))
check('REAL DUMP (中身の変更): 中身が同じなら変更なし', run(REAL_DUMP_CONTENT), [])

# 1. 既存ファイルの中身の変更 (write は一時名、時刻は実名)
put(old_dir, 'chg.txt', 'before'); put(new_dir, 'chg.txt', 'after')
check('既存ファイルの中身の変更は M',
      run('mkfile ./c/chg.txt.o3-1-0\nwrite ./c/chg.txt.o3-1-0\nrename ./c/chg.txt.o3-1-0 dest=./c/chg.txt\nutimes ./c/chg.txt\n'),
      [('M', 'chg.txt')])

# 2. 同じ中身で書き直しただけ (extent は付け替わるが、中身も mtime も同じ) は変更なし
put(old_dir, 'same.bin', 'zzzz'); put(new_dir, 'same.bin', 'zzzz')
st = os.lstat(os.path.join(old_dir, 'same.bin'))
os.utime(os.path.join(new_dir, 'same.bin'), ns=(st.st_atime_ns, st.st_mtime_ns))
check('同じ中身の書き直しは変更なし',
      run('mkfile ./c/same.bin.o1-1-0\nwrite ./c/same.bin.o1-1-0\nrename ./c/same.bin.o1-1-0 dest=./c/same.bin\n'),
      [])

# 3. atime だけの変化 (読んだだけ) は変更なし
put(old_dir, 'read.txt', 'abc'); put(new_dir, 'read.txt', 'abc')
st = os.lstat(os.path.join(old_dir, 'read.txt'))
os.utime(os.path.join(new_dir, 'read.txt'), ns=(st.st_atime_ns, st.st_mtime_ns))
check('atime だけの変化は変更なし', run('utimes ./c/read.txt\n'), [])

# 4. 新規ファイル (親に無い名前)
put(new_dir, 'new.txt', 'new')
check('新規ファイルは A',
      run('mkfile ./c/new.txt.o1-1-0\nwrite ./c/new.txt.o1-1-0\nrename ./c/new.txt.o1-1-0 dest=./c/new.txt\nutimes ./c/new.txt\n'),
      [('A', 'new.txt')])

# 5. 新規ディレクトリ (実機と同じ形)
check('新規ディレクトリは A',
      run('mkdir ./c/o1-2-0\nrename ./c/o1-2-0 dest=./c/nd\nchown ./c/nd\nchmod ./c/nd\nutimes ./c/nd\n'),
      [('A', 'nd')])

# 6. 削除
put(old_dir, 'big.bin', 'x')
check('削除は D', run('unlink ./c/big.bin\n'), [('D', 'big.bin')])

# 7. 既存ファイルの名前の変更 (link と unlink)
put(old_dir, 'a.txt', 'payload'); put(new_dir, 'b.txt', 'payload')
check('名前の変更は、新しい名前の A と古い名前の D',
      run('link ./c/b.txt dest=./c/a.txt\nunlink ./c/a.txt\n'),
      [('A', 'b.txt'), ('D', 'a.txt')])

# 8. 名前の変更と中身の変更が同時
put(old_dir, 'r.txt', 'body1'); put(new_dir, 'r2.txt', 'body2')
check('名前の変更と中身の変更は、新しい名前の A と古い名前の D',
      run('link ./c/r2.txt dest=./c/r.txt\nunlink ./c/r.txt\n'),
      [('A', 'r2.txt'), ('D', 'r.txt')])

# 9. 既存ファイルの chmod だけ (実名)
put(old_dir, 'cm.txt', 'x'); put(new_dir, 'cm.txt', 'x')
check('chmod だけでも M', run('chmod ./c/cm.txt\n'), [('M', 'cm.txt')])

# 10. 消して作り直した (D の後に同じ名前で作る)
put(old_dir, 're.txt', 'a'); put(new_dir, 're.txt', 'b')
check('消して作り直したら M',
      run('unlink ./c/re.txt\nmkfile ./c/re.txt.o1-1-0\nwrite ./c/re.txt.o1-1-0\nrename ./c/re.txt.o1-1-0 dest=./c/re.txt\n'),
      [('M', 're.txt')])

# 11. ディレクトリごと削除
put(old_dir, 'd/x.txt', 'x')
check('削除したディレクトリとその中身は D',
      run('unlink ./c/d/x.txt\nrmdir ./c/d\n'),
      [('D', 'd'), ('D', 'd/x.txt')])

# 12. 空白を含む名前 (send は空白を \\ でエスケープする)
put(old_dir, 'odd d/x y.txt', 'v1'); put(new_dir, 'odd d/x y.txt', 'v2')
check('空白を含む名前の変更は M',
      run('mkfile ./c/odd\\ d/x\\ y.txt.o1-1-0\nwrite ./c/odd\\ d/x\\ y.txt.o1-1-0\n'
          'rename ./c/odd\\ d/x\\ y.txt.o1-1-0 dest=./c/odd\\ d/x\\ y.txt\n'),
      [('M', 'odd d/x y.txt')])

print('\nFAILED' if fails else '\nALL PASSED', f'({fails} failures)')
shutil.rmtree(old_dir); shutil.rmtree(new_dir)
sys.exit(1 if fails else 0)
