# clayfs の Linux 版（btrfs）: 設計メモ

macOS 版（APFS）の仕組みを、btrfs に置き換える。目的は、macOS で必要だった回避策
（sparsebundle、ゼロ埋め、HolePunch、compact）を、なるべく不要にすること。

## 対応表

| macOS 版（APFS） | Linux 版（btrfs） |
|---|---|
| sparsebundle に入れて隠す | 不要。btrfs のボリュームを直接使う |
| `clonefile` によるクローン | reflink（`FICLONE`、`cp --reflink=always`） |
| コミットを `clone_tree` で複製 | 読み取り専用の subvolume スナップショット |
| `ditto --hfsCompression` / `UF_COMPRESSED` | 圧縮（`compress=zstd`、`chattr +c`） |
| `keep` の方針（圧縮を保つパス） | 対象ディレクトリに `chattr +c`（新規ファイルに継承）、既存は `btrfs filesystem defragment -c` |
| `hdiutil compact` と HolePunch | `fstrim`（`discard` で下の層へ伝わる）。ゼロ埋めは不要の見込み |
| xattr と `chflags` | xattr と `FS_IOC_SETFLAGS`（chattr） |
| `lsof` による開いているファイルの確認 | `/proc/*/fd` を読む |
| 再構築（`rebuild`） | `btrfs send | btrfs receive`（履歴も移せる） |
| `scrub`（SHA-256 の照合） | `btrfs scrub`（データのチェックサム）＋ SHA-256 の索引 |
| `dedup` | reflink の付け替えは同じ考え方。重複の検出は既存の索引を使う |
| launchd | systemd のタイマー（毎時のコミット、夜間の保守） |

## 残すもの（OS に依らない）

- 索引（SQLite）の SHA-256、`scrub`、`dedup` の考え方
- `keep` / `unkeep` の方針（パス単位の圧縮保持）
- コミットの記録（`log.jsonl`、変更一覧）
- 一時ファイルは作業ツリーの外（ストアの中）に作る

## 注意点

- **defrag は reflink の共有を崩す。** 容量が増えることがある。使う場合は慎重に。
- **スナップショットの数。** 毎時のコミットを何日分残すかを先に決める（保持方針）。
- **`dedup` と reflink。** btrfs の reflink は、extent 単位の共有。ファイル単位で同じ内容をまとめる方式が、そのまま効くかは要確認。
- **書き込みの途中での参照。** スナップショットは一瞬で作れるが、開いているファイルの扱いは `/proc` で確かめる。

## PoC の順番（Linux 環境が必要）

1. btrfs のループイメージを作り、マウントする。
2. reflink で作業ツリーを複製し、読み取り専用スナップショットを「コミット」として取る。
3. 変更して、差分（変わったファイル）が取れることを確かめる。
4. `keep` 相当の圧縮（`chattr +c`）と `btrfs filesystem defragment -c` の動きを確かめる。
5. `btrfs scrub` を走らせ、結果を確認する。
6. 容量の増減を、コミットを重ねながら測る。

## 未決め

- 検証の Linux 環境（実機、VM、Docker のどれか）。
- スナップショットの保持方針。
- 作業ツリーのパス（`CLAYFS_DIR` の扱い）。
