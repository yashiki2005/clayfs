#!/usr/bin/env python3
"""レビューで見つかった問題を直したことを確かめるテスト。使い捨ての APFS イメージ (sparsebundle) の中で動く。

実際のストア (~/.src.clayfs) には触れない。clayfs_tool を -s / -C 付きで直接呼ぶ。
使い方: python3 experiments/test_review_fixes.py
"""
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.abspath(os.path.join(HERE, '..', 'clayfs_tool'))
passed = failed = 0


def check(name, cond, extra=''):
    global passed, failed
    if cond:
        passed += 1
        print(f'  ok:   {name}')
    else:
        failed += 1
        print(f'  FAIL: {name} {extra}')


def run(vol, *args, **kw):
    r = subprocess.run([sys.executable, '-I', TOOL, '-s', f'{vol}/store', '-C', f'{vol}/work', *args],
                       capture_output=True, text=True, **kw)
    return r


def make_volume():
    base = tempfile.mkdtemp(prefix='clayfs-test.')
    img = os.path.join(base, 't.sparsebundle')
    vol = os.path.join(base, 'vol')
    os.mkdir(vol)
    subprocess.run(['hdiutil', 'create', '-size', '300m', '-type', 'SPARSEBUNDLE', '-fs', 'APFS', '-volname', 'CLAYT', img],
                   check=True, capture_output=True)
    subprocess.run(['hdiutil', 'attach', '-nobrowse', '-owners', 'on', '-mountpoint', vol, img], check=True, capture_output=True)
    os.makedirs(f'{vol}/work')
    return base, vol


def drop_volume(base, vol):
    for _ in range(5):
        if subprocess.run(['hdiutil', 'detach', vol], capture_output=True).returncode == 0:
            break
        time.sleep(1)
    else:
        subprocess.run(['hdiutil', 'detach', '-force', vol], capture_output=True)
    shutil.rmtree(base, ignore_errors=True)


def w(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as f:
        f.write(data)


def same_mtime_rewrite(path, data):
    """大きさも更新時刻も変えずに中身を書き換える"""
    s = os.lstat(path)
    with open(path, 'r+b') as f:
        f.write(data)
    os.utime(path, ns=(s.st_atime_ns, s.st_mtime_ns))


def t_dedup_open_file(vol):
    print('[dedup: 開かれているファイル]')
    blob = os.urandom(300000)
    w(f'{vol}/work/a.bin', blob)
    w(f'{vol}/work/b.bin', blob)
    holder = subprocess.Popen([sys.executable, '-c',
        "import sys,time\nf=open(sys.argv[1],'r+b')\nprint('r',flush=True)\nsys.stdin.readline()\nf.seek(0,2);f.write(b'APPENDED-DATA!!')\nf.flush()\n",
        f'{vol}/work/b.bin'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
    holder.stdout.readline()
    r = run(vol, 'dedup')
    holder.stdin.write('\n'); holder.stdin.flush(); holder.wait()
    size = os.path.getsize(f'{vol}/work/b.bin')
    check('開かれているファイルは差し替えない (追記が残る)', size == 300015, f'size={size}\n{r.stdout}{r.stderr}')


def t_dedup_stale_index(vol):
    print('[dedup: 大きさと更新時刻が同じ書き換え]')
    blob = os.urandom(200000)
    w(f'{vol}/work/x.bin', blob)
    w(f'{vol}/work/y.bin', blob)
    run(vol, 'dedup', '--dry-run')
    r = run(vol, 'dedup')      # 索引に両方を入れる (ここで共有される)
    same_mtime_rewrite(f'{vol}/work/y.bin', b'NEW-CONTENT-XYZ')   # 共有を壊す書き換え
    # 共有後の書き込みで inode が変わらない場合の検査は難しいので、索引を作ってから書き換える別の組で確かめる
    blob2 = os.urandom(200000)
    w(f'{vol}/work/p.bin', blob2)
    w(f'{vol}/work/q.bin', blob2)
    run(vol, 'dedup', '--dry-run')                       # 索引のハッシュは p == q
    run(vol, 'compress', '--dry-run')
    # 索引を作るのは dedup 自体なので、いったん index を更新するため status を呼ぶ代わりに、
    # 更新時刻を保って q を書き換える (索引は p == q のまま)
    from_idx = run(vol, 'dedup', '--dry-run')
    same_mtime_rewrite(f'{vol}/work/q.bin', b'MODIFIED-Q')
    run(vol, 'dedup')
    with open(f'{vol}/work/q.bin', 'rb') as f:
        head = f.read(10)
    check('更新時刻を保った書き換えが、dedup で消えない', head == b'MODIFIED-Q', f'head={head!r}')


def t_dedup_identity(vol):
    print('[dedup: 所有者・グループ・リソースフォーク]')
    blob = os.urandom(150000)
    w(f'{vol}/work/g1.bin', blob)
    w(f'{vol}/work/g2.bin', blob)
    r1 = run(vol, 'dedup', '--dry-run')
    # g2 だけにリソースフォークを付ける
    with open(f'{vol}/work/g2.bin/..namedfork/rsrc', 'wb') as f:
        f.write(b'RSRC-DATA-18-bytes')
    # グループを変える (取れるグループのうち現在と違うもの)
    gid_now = os.lstat(f'{vol}/work/g1.bin').st_gid
    groups = [g for g in os.getgroups() if g != gid_now]
    if groups:
        os.chown(f'{vol}/work/g1.bin', -1, groups[0])
    r = run(vol, 'dedup')
    with open(f'{vol}/work/g2.bin/..namedfork/rsrc', 'rb') as f:
        rs = f.read()
    check('本物のリソースフォークを持つファイルは触らない', rs == b'RSRC-DATA-18-bytes', f'{rs!r}\n{r.stdout}{r.stderr}')
    # グループ: 別の組で確かめる
    blob = os.urandom(150000)
    w(f'{vol}/work/h1.bin', blob)
    w(f'{vol}/work/h2.bin', blob)
    groups = [g for g in os.getgroups() if g != os.lstat(f'{vol}/work/h2.bin').st_gid]
    if groups:
        os.chown(f'{vol}/work/h2.bin', -1, groups[0])
        want = groups[0]
        run(vol, 'dedup')
        check('dedup 後もグループが変わらない', os.lstat(f'{vol}/work/h2.bin').st_gid == want)
    else:
        print('  (取れるグループが 1 つだけなので、グループの検査は省略)')


def t_json_robust(vol):
    print('[状態ファイルの壊れ]')
    run(vol, 'commit', '-m', 'one')
    log = f'{vol}/store/log.jsonl'
    with open(log, 'a') as f:
        f.write('{"name": "broken", "mess')       # 書いている途中で止まった行
    r = run(vol, 'log')
    check('log.jsonl の途中の行があっても log が動く', r.returncode == 0 and 'Traceback' not in r.stderr, r.stderr[-200:])
    time.sleep(1.1)
    w(f'{vol}/work/new.txt', b'x')
    r = run(vol, 'commit', '-m', 'two')
    check('途中の行のあとでも commit できる', r.returncode == 0, r.stderr[-200:])
    r = run(vol, 'log')
    check('新しい行が壊れた行と混ざらない', r.stdout.count('two') >= 1, r.stdout)
    with open(f'{vol}/store/work.json', 'w') as f:
        f.write('')
    r = run(vol, 'status')
    check('work.json が壊れていれば、例外ではなく案内で止まる', r.returncode != 0 and 'Traceback' not in r.stderr and 'work.json' in r.stderr, r.stderr[-300:])


def t_commit_unreadable(vol):
    print('[commit: 読めないディレクトリ]')
    w(f'{vol}/work/ok.txt', b'ok')
    w(f'{vol}/work/secret/inner.txt', b'hidden')
    os.chmod(f'{vol}/work/secret', 0)
    try:
        time.sleep(1.1)
        r = run(vol, 'commit', '-m', 'unreadable')
        check('読めないディレクトリがあっても commit が落ちない', r.returncode == 0 and 'Traceback' not in r.stderr, r.stderr[-300:])
        r = run(vol, 'status')
        check('status も落ちない', 'Traceback' not in r.stderr, r.stderr[-300:])
    finally:
        os.chmod(f'{vol}/work/secret', 0o755)


def t_gc_immutable(vol):
    print('[gc: 変更禁止のファイルと読み取り専用ディレクトリ]')
    w(f'{vol}/work/lock/f.txt', b'locked')
    os.chflags(f'{vol}/work/lock/f.txt', stat.UF_IMMUTABLE)
    os.chmod(f'{vol}/work/lock', 0o555)
    time.sleep(1.1)
    run(vol, 'commit', '-m', 'with-lock')
    os.chflags(f'{vol}/work/lock/f.txt', 0)
    os.chmod(f'{vol}/work/lock', 0o755)
    for i in range(3):
        time.sleep(1.1)
        w(f'{vol}/work/g{i}.txt', b'x' * (i + 1))
        run(vol, 'commit', '-m', f'later{i}')
    r = run(vol, 'gc', '--keep', '2')
    check('変更禁止のファイルを含むコミットも gc で消える', r.returncode == 0 and 'Traceback' not in r.stderr, r.stderr[-300:])
    left = [n for n in os.listdir(f'{vol}/store/layers') if not n.startswith('.')]
    check('gc のあと、中身が残っているのは新しい 2 個だけ',
          sum(1 for n in left if os.path.isdir(f'{vol}/store/layers/{n}/fs')) == 2, str(left))


def t_rebuild_failure(vol):
    print('[rebuild-into: コピーできなかったファイル]')
    w(f'{vol}/work/readable.txt', b'fine')
    w(f'{vol}/work/unreadable.txt', b'cannot read me')
    run(vol, 'commit', '-m', 'r')
    os.chmod(f'{vol}/work/unreadable.txt', 0)
    new = os.path.join(vol, 'newroot')
    os.makedirs(new)
    try:
        r = run(vol, 'rebuild-into', new, '--mode', 'fresh')
        check('コピーに失敗したら終了コードが 0 ではない', r.returncode != 0, f'rc={r.returncode}\n{r.stdout}{r.stderr}')
    finally:
        os.chmod(f'{vol}/work/unreadable.txt', 0o644)


def main():
    tests = [t_dedup_open_file, t_dedup_stale_index, t_dedup_identity, t_json_robust,
             t_commit_unreadable, t_gc_immutable, t_rebuild_failure]
    only = sys.argv[1:]
    for t in tests:
        if only and t.__name__ not in only:
            continue
        base, vol = make_volume()
        try:
            t(vol)
        finally:
            drop_volume(base, vol)
    print(f'結果: {passed} passed, {failed} failed')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
