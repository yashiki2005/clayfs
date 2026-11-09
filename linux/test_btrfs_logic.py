#!/usr/bin/env python3
"""clayfs_btrfs の Python 部分 (鍵、commit/run/gc/status/restore の流れ、パスの検査) のテスト。

btrfs の無い環境でも動く: subvolume の create/snapshot/delete と chattr だけをモックし、
差分は手で与える。使い方: python3 linux/test_btrfs_logic.py [clayfs_btrfs のパス]"""
import sys as _sys_check
if len(_sys_check.argv) < 2:
    import os as _os
    _sys_check.argv.append(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), 'clayfs_btrfs'))
import importlib.machinery, importlib.util, os, shutil, sys, tempfile, argparse, subprocess

HERE = os.path.dirname(os.path.abspath(sys.argv[1]))
loader = importlib.machinery.SourceFileLoader('cbt', sys.argv[1])
spec = importlib.util.spec_from_loader('cbt', loader); m = importlib.util.module_from_spec(spec); loader.exec_module(m)

root = tempfile.mkdtemp(prefix='cbt-')
MNT = os.path.join(root, 'mnt'); os.makedirs(MNT)
m.os.path.ismount = lambda p: True            # 偽のマウント
real_run = m.run
def fake_run(args, check=True, capture=True):
    a = list(args)
    if a[:2] == ['btrfs', 'subvolume'] and a[2] == 'snapshot':
        rest = [x for x in a[3:] if x != '-r']
        shutil.copytree(rest[0], rest[1], symlinks=True)
        if '-r' in a[3:]:
            for dp, ds, fs in os.walk(rest[1]):
                for n in ds + fs:
                    q = os.path.join(dp, n); os.chmod(q, os.lstat(q).st_mode & ~0o222)
        return subprocess.CompletedProcess(a, 0, '', '')
    if a[:2] == ['btrfs', 'subvolume'] and a[2] == 'delete':
        if os.path.lexists(a[3]):
            def un(r):
                for dp, ds, fs in os.walk(r):
                    os.chmod(dp, 0o700)
                    for n in ds+fs: os.chmod(os.path.join(dp,n), 0o700)
            un(a[3]); shutil.rmtree(a[3])
        return subprocess.CompletedProcess(a, 0, '', '')
    if a[:2] == ['btrfs', 'subvolume'] and a[2] in ('create', 'sync'):
        if a[2] == 'create': os.makedirs(a[3], exist_ok=True)
        return subprocess.CompletedProcess(a, 0, '', '')
    if a[:1] == ['chattr']: return subprocess.CompletedProcess(a, 0, '', '')
    if a[:1] == ['cp']:
        # macOS の cp は --reflink=always を実現できないので、無しで行う (Linux では不要な分岐)
        a2 = [x for x in a if not x.startswith('--reflink')]
        return subprocess.run(a2, capture_output=True, text=True)
    if a[:1] == ['diff']:
        return subprocess.run(a, capture_output=True, text=True)
    if a[:2] == ['btrfs', 'filesystem']: return subprocess.CompletedProcess(a, 0, '', '')
    return subprocess.CompletedProcess(a, 0, '', '')
m.run = fake_run
m.os.sync = lambda *_: None

vol = m.Vol(MNT)
os.makedirs(vol.store, exist_ok=True)
os.makedirs(vol.layers, exist_ok=True)
os.makedirs(vol.work, exist_ok=True)

# 差分: 実際の parse_dump に、テストで作った dump を渡す (diff_snapshots を置き換え)
def fake_diff(vol_, old, new):
    return CURRENT_DIFF
m.diff_snapshots = fake_diff

def ns(**kw):
    d = dict(name=None, message=None, allow_empty=False, short=False, gen=None, source=None,
             all=False, paths=[], keep=100, dry_run=False, n=None, remove=[], fn=None)
    d.update(kw); return argparse.Namespace(**d)

fails = 0
def check(name, cond, extra=''):
    global fails
    print(('ok   ' if cond else 'FAIL ') + name + (f'  {extra}' if extra and not cond else ''))
    if not cond: fails += 1

CURRENT_DIFF = []
# 1. 初回コミット
m.cmd_commit(vol, ns(message='first', allow_empty=True))
check('初回コミットで HEAD ができる', m.head(vol) is not None)
# 2. 変更なし -> コミットしない
m.cmd_commit(vol, ns(message='nothing'))
check('変更なしならコミットしない', len(m.load_log(vol)) == 1)
# 3. 変更あり
open(os.path.join(vol.work, 'a.txt'), 'w').write('x')
CURRENT_DIFF = [('M', 'a.txt')]
m.cmd_commit(vol, ns(message='second'))
check('変更ありならコミットする', len(m.load_log(vol)) == 2)
# 4. run: 変化なし (same_generation は常に False になるようモック)
m.same_generation = lambda v: False
CURRENT_DIFF = []
m.cmd_run(vol, ns())
check('run: 変更なしなら何もしない', len(m.load_log(vol)) == 2)
CURRENT_DIFF = [('A', 'b.txt')]
m.cmd_run(vol, ns())
check('run: 変更ありならコミットする', len(m.load_log(vol)) == 3)
# 5. run の二重実行は片方だけ
m.same_generation = lambda v: False
fd = m.try_lock(vol)
CURRENT_DIFF = [('A', 'c.txt')]
m.cmd_run(vol, ns())
check('run: 他の実行中なら何もしない (鍵がある)', len(m.load_log(vol)) == 3)
os.close(fd)
# 6. gc は HEAD を残す
m.cmd_gc(vol, ns(keep=1))
names_after = [e['name'] for e in m.load_log(vol)]
check('gc --keep 1: HEAD の中身が残る', os.path.isdir(vol.layer(names_after[-1])))
check('gc --keep 1: 古い世代は消える', not os.path.isdir(vol.layer(names_after[0])))
# 7. status は鍵の中で動く (入れ子の lock は die しないこと = 外側を持たない)
CURRENT_DIFF = [('M', 'a.txt')]
m.cmd_status(vol, ns(short=True))
check('status が動く', True)
# 8. restore のパス検査
try:
    m.cmd_restore(vol, ns(source=names_after[-1], paths=['../etc/passwd']))
    check('restore: .. を拒む', False)
except SystemExit:
    check('restore: .. を拒む', True)
# 9. restore 正常系: まず sub/f.txt を入れてコミットし、それを書き換えてから戻す
os.makedirs(os.path.join(vol.work, 'sub'), exist_ok=True)
open(os.path.join(vol.work, 'sub', 'f.txt'), 'w').write('then')
CURRENT_DIFF = [('A', 'sub/f.txt')]
m.cmd_commit(vol, ns(message='with sub'))
gen = m.load_log(vol)[-1]['name']  # 完全な名前 (前方一致の別世代と衝突させない)
open(os.path.join(vol.work, 'sub', 'f.txt'), 'w').write('now')
m.cmd_restore(vol, ns(source=gen, paths=["sub/f.txt"]))
check('restore: 中身が戻る', open(os.path.join(vol.work, 'sub', 'f.txt')).read() == 'then')
check('restore: 退避が残る', os.path.isdir(vol.trash) and any(os.scandir(vol.trash)))
# 10. keep 一覧
open(os.path.join(vol.store, 'keep.json'), 'w').write('["src"]')
check('keep: _under が下も含む', m._under('src/a/b.txt', m.load_keep(vol)))
check('keep: 別名は含まない', not m._under('srcx/a.txt', m.load_keep(vol)))
# 11. safe_rel
for bad in ['..', '../x', '/abs', '.', '']:
    try: m.safe_rel(bad); check(f'safe_rel が拒む {bad!r}', False)
    except SystemExit: check(f'safe_rel が拒む {bad!r}', True)
check('safe_rel が通す', m.safe_rel('a/b') == 'a/b')

shutil.rmtree(root, ignore_errors=True)
print('\nFAILED' if fails else '\nALL PASSED', f'({fails})')
sys.exit(1 if fails else 0)
