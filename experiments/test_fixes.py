#!/usr/bin/env python3
"""compress レビューの指摘を直したことを確かめるテスト。

- 差し替え中の書き込みを失わない (replace_checked)
- 一時ファイルは作業ツリーに残らず、途中終了の残骸は次の実行で消える
- park / unpark の引数は、作業ツリーの中のプロジェクト名にだけ解決される
- 下の項目を削除しても、名前が似た別の項目の索引は消えない (LIKE の誤一致)
"""
import importlib.machinery
import importlib.util
import os
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.abspath(os.path.join(HERE, '..', 'clayfs_tool'))

# 拡張子のないスクリプトなので、ローダーを明示して読み込む
_loader = importlib.machinery.SourceFileLoader('clayfs_tool_under_test', TOOL)
_spec = importlib.util.spec_from_loader('clayfs_tool_under_test', _loader)
ct = importlib.util.module_from_spec(_spec)
_loader.exec_module(ct)


def write(path, text):
    with open(path, 'w') as f:
        f.write(text)


def read(path):
    with open(path) as f:
        return f.read()


def test_replace_checked_success(root):
    scratch = ct.scratch_dir(ct.Store(os.path.join(root, 'store')))
    path = os.path.join(root, 'f.txt')
    write(path, 'old')
    old = time.time() - 86400
    os.utime(path, (old, old))
    s = os.lstat(path)
    tmp = os.path.join(scratch, 'new.tmp')
    write(tmp, 'new')
    assert ct.replace_checked(path, tmp, s, scratch) is True
    assert read(path) == 'new', 'the replacement should be in place'
    assert os.listdir(scratch) == [], f'no backup should remain: {os.listdir(scratch)}'
    print('  replace_checked: 変更がなければ差し替える、退避は残さない')


def test_replace_checked_keeps_concurrent_write(root):
    store = ct.Store(os.path.join(root, 'store'))
    scratch = ct.scratch_dir(store)
    path = os.path.join(root, 'f.txt')
    write(path, 'old')
    old = time.time() - 86400
    os.utime(path, (old, old))
    s = os.lstat(path)
    # 圧縮の途中で、書き込みが入った (差し替えの前に元の実体へ書かれた状態を作る)
    with open(path, 'a') as f:
        f.write(' + written by a user')
    tmp = os.path.join(scratch, 'new.tmp')
    write(tmp, 'compressed-old-content')
    assert ct.replace_checked(path, tmp, s, scratch) is False, 'a concurrent write must cancel the swap'
    assert read(path) == 'old + written by a user', f'the user write was lost: {read(path)!r}'
    assert os.listdir(scratch) == [], f'nothing should be left behind: {os.listdir(scratch)}'
    print('  replace_checked: 差し替え中の書き込みは失われず、差し替えを取り消す')


def test_scratch_sweep_and_no_temp_in_work(root):
    store = ct.Store(os.path.join(root, 'store'))
    work = os.path.join(root, 'work')
    os.makedirs(os.path.join(work, 'proj'))
    scratch = ct.scratch_dir(store)
    # 途中終了で残ったものを模す (ファイルと入れ子のディレクトリ)
    write(os.path.join(scratch, 'comp.123.1'), 'leftover')
    os.makedirs(os.path.join(scratch, 'old.nested'))
    ct.prepare_scratch(store, work)
    assert os.listdir(scratch) == [], f'leftovers should be swept: {os.listdir(scratch)}'
    # 残骸は作業ツリーに現れず、コミットの走査にも入らない
    names = [rel for rel, _ in ct.walk_files(work)]
    assert not any('.clayfs-' in n for n in names), names
    print('  scratch: 途中終了の残骸を次の実行で消す。作業ツリーには一時ファイルを作らない')


def test_project_name(root):
    work = os.path.join(root, 'work')
    os.makedirs(os.path.join(work, 'proj', 'sub'))
    assert ct.project_name(work, 'proj') == 'proj'
    assert ct.project_name(work, 'proj/sub') == 'proj'
    assert ct.project_name(work, os.path.join(work, 'proj', 'sub')) == 'proj'
    for bad in ['.', '..', '../outside', '/tmp']:
        try:
            ct.project_name(work, bad)
        except SystemExit:
            continue
        raise AssertionError(f'{bad!r} should be refused')
    print('  project_name: 作業ツリー内のプロジェクト名だけを受け付ける (絶対パスは先頭だけを取らない)')


def test_like_delete_is_exact(root):
    store = ct.Store(os.path.join(root, 'store'))
    work = os.path.join(root, 'work')
    os.makedirs(work)
    ct.WORK_DIR = work
    db = ct.index_db(store)
    rows = ['a_b', 'a_b/x', 'aXb/x', 'a%b/y', 'a%b', 'aZb/z']
    for p in rows:
        db.execute('INSERT INTO files (path, size, mtime_ns, ino, sha256, shared_with) VALUES (?,?,?,?,?,NULL)',
                   (p, 1, 1, 1, 'h'))
    db.commit()
    db.close()
    ct.index_changes(store, [('D', 'a_b/'), ('D', 'a%b/')])
    db = ct.index_db(store)
    left = sorted(r[0] for r in db.execute('SELECT path FROM files'))
    db.close()
    assert left == ['aXb/x', 'aZb/z'], f'wrong rows left: {left}'
    print('  index: 削除は下の項目だけ。_ や % を含む名前が、ほかの項目を巻き込まない')


def test_pycache_is_pruned(root):
    import subprocess
    store = os.path.join(root, 'store')
    work = os.path.join(root, 'work')
    os.makedirs(os.path.join(work, 'proj', '__pycache__'))
    os.makedirs(os.path.join(work, '__pycache__'))
    write(os.path.join(work, 'proj', 'a.py'), 'print(1)\n')
    write(os.path.join(work, 'proj', '__pycache__', 'a.cpython-314.pyc'), 'bytecode-1')
    write(os.path.join(work, '__pycache__', 'top.pyc'), 'bytecode-top')

    def tool(*args):
        return subprocess.run([sys.executable, TOOL, '-s', store, '-C', work, *args],
                              capture_output=True, text=True)

    r = tool('commit', '-m', 'init')
    assert r.returncode == 0, r.stderr
    layers = sorted(n for n in os.listdir(os.path.join(store, 'layers')) if not n.startswith('.'))
    fs = os.path.join(store, 'layers', layers[-1], 'fs')
    assert os.path.exists(os.path.join(fs, 'proj', 'a.py')), 'source must be committed'
    assert not os.path.exists(os.path.join(fs, 'proj', '__pycache__')), 'nested pycache must not be committed'
    assert not os.path.exists(os.path.join(fs, '__pycache__')), 'top-level pycache must not be committed'
    # 生成物だけが変わっても、変更とはみなさない
    write(os.path.join(work, 'proj', '__pycache__', 'a.cpython-314.pyc'), 'bytecode-2 changed')
    r = tool('status')
    assert '変更はありません' in r.stdout, f'pycache change must not show: {r.stdout}'
    names = [rel for rel, _ in ct.walk_files(work)]
    assert not any('__pycache__' in n.split(os.sep) for n in names), names
    print('  pycache: コミットにも差分にも走査にも入らない (どの階層でも)')


def main():
    print('=== compress レビュー指摘の修正テスト ===')
    root = os.path.abspath('test_clayfs_fixes_env')
    if os.path.exists(root):
        shutil.rmtree(root)
    os.makedirs(root)
    try:
        for name in ['test_replace_checked_success', 'test_replace_checked_keeps_concurrent_write',
                     'test_scratch_sweep_and_no_temp_in_work', 'test_project_name', 'test_like_delete_is_exact',
                     'test_pycache_is_pruned']:
            case = os.path.join(root, name)
            os.makedirs(case)
            globals()[name](case)
        print('=== 全テスト合格 (ALL TESTS PASSED) ===')
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == '__main__':
    sys.exit(main())
