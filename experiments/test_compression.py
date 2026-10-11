#!/usr/bin/env python3
"""APFS 透過圧縮、keep / unkeep、compress の動作検証テスト。"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
CLAYFS_TOOL = os.path.abspath(os.path.join(HERE, '..', 'clayfs_tool'))
CLAYFSCTL = os.path.abspath(os.path.join(HERE, '..', 'clayfsctl'))

UF_COMPRESSED = 0x20


def run_tool(store, work, *args):
    cmd = [sys.executable, CLAYFS_TOOL, '-s', store, '-C', work] + list(args)
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r


def main():
    print("=== APFS 透過圧縮テスト開始 ===")

    # APFSボリューム上 (work_dirの直下) にテスト用ディレクトリを作成
    test_root = os.path.abspath("test_clayfs_compress_env")
    if os.path.exists(test_root):
        shutil.rmtree(test_root)
    os.makedirs(test_root)

    try:
        work = os.path.join(test_root, "work")
        store = os.path.join(test_root, "store")
        os.makedirs(work)
        os.makedirs(store)

        # プロジェクト作成
        proj_old = os.path.join(work, "proj_old")
        proj_new = os.path.join(work, "proj_new")
        proj_park = os.path.join(work, "proj_park")
        os.makedirs(proj_old)
        os.makedirs(proj_new)
        os.makedirs(proj_park)

        # 1. 圧縮可能なテキストファイル (80KB)
        old_txt = os.path.join(proj_old, "large.txt")
        with open(old_txt, "w") as f:
            f.write("Line of compressible text data repeated.\n" * 2000)
        # mtime を 10 日前に設定
        ten_days_ago = time.time() - 10 * 86400
        os.utime(old_txt, (ten_days_ago, ten_days_ago))

        # 2. 新しいファイル (1時間前) - 圧縮対象外 (7日未満)
        new_txt = os.path.join(proj_new, "recent.txt")
        with open(new_txt, "w") as f:
            f.write("Recent compressible text data repeated.\n" * 2000)

        # 3. 畳む (park) プロジェクト内の新しいファイル - park されると圧縮対象
        park_txt = os.path.join(proj_park, "parked_data.txt")
        with open(park_txt, "w") as f:
            f.write("Parked compressible text data repeated.\n" * 2000)

        # 4. 除外対象: 4KB 以下の小さいファイル
        small_file = os.path.join(proj_old, "small.txt")
        with open(small_file, "w") as f:
            f.write("short text")
        os.utime(small_file, (ten_days_ago, ten_days_ago))

        # 5. 除外対象: 圧縮済み拡張子 (.png)
        png_file = os.path.join(proj_old, "image.png")
        with open(png_file, "wb") as f:
            f.write(os.urandom(10000))
        os.utime(png_file, (ten_days_ago, ten_days_ago))

        # 6. 除外対象: データベース (.db)
        db_file = os.path.join(proj_old, "data.db")
        with open(db_file, "wb") as f:
            f.write(b"SQLite format 3\x00" + b"\x00" * 10000)
        os.utime(db_file, (ten_days_ago, ten_days_ago))

        # 初回コミット
        print("-> 初回コミット作成...")
        r = run_tool(store, work, "commit", "-m", "initial")
        assert r.returncode == 0, f"commit failed: {r.stderr}"

        # 状態確認
        r = run_tool(store, work, "status")
        assert "変更はありません" in r.stdout, f"status not clean: {r.stdout}"

        # --- テスト 1: dry-run ---
        print("-> テスト 1: compress --dry-run")
        r = run_tool(store, work, "compress", "--dry-run")
        assert r.returncode == 0, f"compress --dry-run failed: {r.stderr}"
        print("   output:", r.stdout.strip())
        assert "圧縮対象: 1 ファイル" in r.stdout, f"Expected 1 candidate (large.txt): {r.stdout}"
        # ファイルがまだ圧縮されていないことを確認
        assert not (os.lstat(old_txt).st_flags & UF_COMPRESSED), "Should not be compressed on dry-run"

        # --- テスト 2: clayfs_tool compress (自動対象: 7日以上経過した large.txt のみ) ---
        print("-> テスト 2: compress 実行")
        blocks_before = os.lstat(old_txt).st_blocks
        r = run_tool(store, work, "compress")
        assert r.returncode == 0, f"compress failed: {r.stderr}"
        print("   output:", r.stdout.strip())

        st_old = os.lstat(old_txt)
        assert st_old.st_flags & UF_COMPRESSED, "large.txt should have UF_COMPRESSED flag"
        assert st_old.st_blocks < blocks_before, f"large.txt blocks should decrease: {st_old.st_blocks} < {blocks_before}"
        print(f"   large.txt 圧縮成功: blocks {blocks_before} -> {st_old.st_blocks}, flags={hex(st_old.st_flags)}")

        # 内容が透過的に読めることを確認
        with open(old_txt, "r") as f:
            content = f.read()
        assert len(content) == len("Line of compressible text data repeated.\n" * 2000)

        # 他のファイルが圧縮されていないことを確認
        assert not (os.lstat(new_txt).st_flags & UF_COMPRESSED), "recent.txt should NOT be compressed"
        assert not (os.lstat(park_txt).st_flags & UF_COMPRESSED), "park_txt should NOT be compressed yet"
        assert not (os.lstat(small_file).st_flags & UF_COMPRESSED), "small.txt should NOT be compressed"
        assert not (os.lstat(png_file).st_flags & UF_COMPRESSED), "image.png should NOT be compressed"
        assert not (os.lstat(db_file).st_flags & UF_COMPRESSED), "data.db should NOT be compressed"

        # 圧縮によって status が変更と誤認されないことを確認
        r = run_tool(store, work, "status")
        assert "変更はありません" in r.stdout, f"status should be clean after compression: {r.stdout}"
        print("   status 検証成功: 透過圧縮を『変更』と誤認しないことを確認")

        # --- テスト 3: パス指定での compress (recent.txt) ---
        print("-> テスト 3: パス指定 compress (proj_new/recent.txt)")
        r = run_tool(store, work, "compress", "proj_new/recent.txt")
        assert r.returncode == 0, f"path compress failed: {r.stderr}"
        st_new = os.lstat(new_txt)
        assert st_new.st_flags & UF_COMPRESSED, "recent.txt should be compressed after explicit path compress"
        print("   recent.txt 明示指定圧縮成功")

        # --- テスト 4: keep (proj_park) ---
        print("-> テスト 4: keep proj_park")
        r = run_tool(store, work, "keep", "proj_park")
        assert r.returncode == 0, f"keep failed: {r.stderr}"
        print("   output:", r.stdout.strip())
        st_park = os.lstat(park_txt)
        assert st_park.st_flags & UF_COMPRESSED, "parked_data.txt should be compressed when its path is kept"

        # 一覧確認
        r = run_tool(store, work, "keep")
        assert "proj_park" in r.stdout, f"keep list should contain proj_park: {r.stdout}"

        # 圧縮を保つ対象は、7 日未満でも compress で再圧縮される (書き換えで戻ったものを含む)
        extra = "one more line\n"
        with open(park_txt, "a") as f:
            f.write(extra)
        assert not (os.lstat(park_txt).st_flags & UF_COMPRESSED), "a write should drop compression"
        r = run_tool(store, work, "compress")
        assert r.returncode == 0, f"compress failed: {r.stderr}"
        assert os.lstat(park_txt).st_flags & UF_COMPRESSED, "kept path should be recompressed without age check"

        # --- テスト 5: unkeep (proj_park) ---
        print("-> テスト 5: unkeep proj_park")
        r = run_tool(store, work, "unkeep", "proj_park")
        assert r.returncode == 0, f"unkeep failed: {r.stderr}"
        print("   output:", r.stdout.strip())
        st_unpark = os.lstat(park_txt)
        assert not (st_unpark.st_flags & UF_COMPRESSED), "parked_data.txt should NOT be compressed after unkeep"
        print("   unkeep 成功: 非圧縮状態に正常復帰")

        # 内容が破損していないことを確認 (追記した行を含む)
        with open(park_txt, "r") as f:
            c = f.read()
        assert len(c) == len("Parked compressible text data repeated.\n" * 2000) + len(extra)
        assert c.endswith(extra)

        # scrub で全ハッシュ照合
        print("-> テスト 6: scrub による整合性検証")
        r = run_tool(store, work, "scrub")
        assert r.returncode == 0, f"scrub failed: {r.stdout} {r.stderr}"
        assert "問題 0" in r.stdout, f"scrub reported issues: {r.stdout}"
        print("   scrub 成功: ハッシュおよび透過圧縮ファイル整合性確認完了")

        print("=== 全テスト合格 (ALL TESTS PASSED) ===")
    finally:
        if os.path.exists(test_root):
            shutil.rmtree(test_root)


if __name__ == "__main__":
    main()
