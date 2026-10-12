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

## 実装の状況

実装: `linux/clayfs_btrfs`（Python、btrfs の CLI を使う）。試験: `linux/test_btrfs.sh`（Pi の特権コンテナで 75 件合格）。

- 済み: init / commit / status / show / log / restore / gc / scrub / dedup / compress / keep / unkeep / run / adopt / rebuild
- 自動実行: `linux/systemd/`（毎時の `run`、毎日の `gc`、毎週の `scrub`）。構文は `systemd-analyze verify` で確認。
  実際のタイマーの動作は、まだ確かめていない（コンテナでは systemd が動かないため）。
- rebuild: 各コミットを `btrfs send -p | receive` で別の btrfs へ移す。未コミット分は rw の work/ として移す。
- adopt: 普通のフォルダ (例 ~/src) を work/ へ複製し、元は SRC.orig に残して、SRC を work/ へのリンクにする。
- インストール: `linux/install.sh MNT [KEEP]`（root が要る）。`--dry-run` で、実行するコマンドだけを表示できる。
  アンインストール: `linux/uninstall.sh`（データと設定は残す）。
- create: `clayfs_btrfs create [SIZE] [--image P] [--mnt D] [--dry-run]`（cfsctl create に当たる）。スパースのイメージを作り、btrfs にフォーマットし、`compress-force=zstd:3` でマウントして init する。既定は 20G、/var/lib/clayfs/clayfs.img、/srv/clayfs。
- link: `clayfs_btrfs MNT link PATH [--owner U]`。利用者が書く場所（例 `~/src`）を `work/` へのリンクにする。実体（btrfs のマウント先）を意識しなくてよい。Mac の `~/src → ~/.src.clayfs/work` と同じ形。`create --link PATH --owner U` で、作成と同時に行える。
- 任意の場所: マウント先（`create --mnt`、`install.sh MNT`）も、書く場所（`link`、`create --link`）も、任意の絶対パスでよい。空白や隠しフォルダを含むパスも試験済み。自動実行のユニットは `"${CLAYFS_MNT}"` と引用している。
- exclude: フォルダ名（どの階層でも一致）で除外する。変更の一覧と重複排除から外れ、再起動なしで次の操作から効く。スナップショットの中身は残る（btrfs は作業ツリーを丸ごと取るため）。履歴にも入れたくないものは、作業ツリーの外に置く。
- info: どこに書けばよいか（書く場所 = work/）、履歴の場所、自動実行の状態を表示する。
- 移行: `linux/migrate_from_dir.sh SRC MNT TOOL`（普通のフォルダから work/ へ。中身とメタデータを照合してから最初のコミットにする。元は消さない）。
- 実機: Pi で、タイマーの起動、変更の検出、初回のコミットを確認済み。
- 変更の検出: send --dump の名前は、空白とバックスラッシュが \ でエスケープされている。名前の変更は link と unlink の組で出るので、link を新しい名前の追加として扱う。
- 変更の検出: スナップショットの前に sync する。時刻だけの変化（atime など、読むだけでも起きる）は変更にしない（mtime が変わったものだけ）。書き出しの時期のずれや同じ中身の書き直しは、extent が付け替わるが、中身（大きさと sha256）が同じなら変更にしない。
- 未実施: 定時の実行 (01:00 など) の自動の確認、gc と scrub の定時実行の確認、Pi の再起動後のマウント (fstab)。

試験で分かったこと（設計に反映済み）:

- 重複排除の容量は、古いスナップショットが実体を掴んでいる間は戻らない（101 → 101 → gc の後 53 MB）。
  保持の方針（何世代残すか）は、重複排除の効果と直結する。
- `btrfs scrub` は全スナップショットの中身を検査するので、macOS 版の `scrub --layers` に相当するものは不要。
- 変更の一覧は `btrfs send --no-data` の差分から取る。大きさと更新時刻に頼らないので、macOS 版の検出の欠陥を避けられる。
- subvolume をまたぐ rename はできない（退避と重複排除の一時ファイルは、同じ subvolume の中に置く）。
- 書き出していないデータ (delalloc) は圧縮し直せない。keep の前に sync する。
