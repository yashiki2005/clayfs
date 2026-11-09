# ClayFS 🏺

> **macOS 向けの次世代 APFS 仮想ドライブ ＆ 超高速タイムマシン**  
> [English](README.md) | **日本語**

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org)
[![APFS CoW](https://img.shields.io/badge/Filesystem-APFS%20CoW-blue)](https://developer.apple.com/documentation/foundation/filemanager)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

ClayFS は、macOS の **APFS Copy-on-Write (`clonefile(2)`)** を活用した、ストレージ消費ゼロで瞬時にスナップショットを作成・復元できる軽量仮想ドライブシステムです。

開発作業中の試行錯誤、巨大なコードベースの変更、Git コミット前の実験的リファクタリングなどを、Finder / CLI の境界なくいつでも自由自在に巻き戻すことができます。

---

## ✨ 主な特長 (Features)

1. **APFS & Btrfs CoW によるゼロコスト・スナップショット**
   - 変更があるまで追加ストレージを一切消費しないミリ秒単位のスナップショット作成（macOS: `clonefile(2)`、Linux: `reflink` / `FICLONE`）。
2. **クロスプラットフォーム対応 (macOS & Linux)**
   - macOS（APFS sparsebundle）と Linux（Btrfs スパースイメージ / ループバック）で、完全に同一の `clayfs` CLI コマンド体系を実現。
3. **Git 感覚のボリューム直接巻き戻し**
   - ドライブのルート全体を直感的にスナップショット＆ロールバック。
   - `.clayfs`、`.fseventsd`、`.Spotlight-V100` などのシステムディレクトリは自動除外され安全に保護。
   - サブパス指定時のパストラバーサル防止および `.clayfs` 内部メタデータの完全保護。
4. **美しい常駐メニューバーアプリ (`ClayFS.app` ※macOS)**
   - スライダーで直感的に時間をさかのぼれるタイムライン・スクラバー。
   - 変更ファイル数の可視化、1クリックでのロールバック確認シート、保持設定。
   - メインスレッドを一切ブロックしない完全非同期バックグラウンドスキャン。
5. **シームレスな空き容量回収 (`compact`)**
   - ドライブ使用中に肥大化したブロックを安全かつ瞬時に回収（macOS: `hdiutil compact`、Linux: `btrfs defragment` & `fstrim`）。
6. **スナップショット保持ポリシー＆自動整理 (`prune`)**
   - 「最大保持件数」や「最大保持日数」を設定可能。スナップショット作成時にも自動プルーニング。
7. **ファイル変更監視デーモン (`watch`)**
   - ファイル変更を監視し、指定時間の静穏（debounce）後に差分がある場合のみ自動でスナップショットを生成（macOS: FSEvents、Linux: ポーリング / inotify）。
8. **ログイン時自動起動＆ドライブ自動マウント**
   - macOS: `SMAppService` / LaunchAgents
   - Linux: `systemd --user`
9. **8言語のネイティブ多言語対応 (i18n)**
   - 主要 8 言語（日本語、英語、簡体字中国語、繁体字中国語、スペイン語、フランス語、ドイツ語、韓国語）に完全対応。OS の言語設定を自動検出します。

---

## 🚀 クイックスタート (Quick Start)

### 必須環境
- **macOS**: macOS 14.0 (Sonoma) 以降、Xcode 16 または Command Line Tools (Swift 6.0)
- **Linux**: Linux カーネル 4.5 以降 (Btrfs サポート)、Swift 6.0、`btrfs-progs`、`libsqlite3-dev`

### インストール (Build & Install)

#### macOS の場合
```bash
git clone https://github.com/yashiki2005/clayfs.git
cd clayfs

# ビルドおよびインストール (CLI: ~/build/bin/clayfs, GUI: ~/Applications/ClayFS.app)
make install
```

#### Linux の場合 (CLI のみ)
```bash
git clone https://github.com/yashiki2005/clayfs.git
cd clayfs

# 依存パッケージと Swift のインストール (Ubuntu/Debian の例)
# Ubuntu 24.04+ では swiftlang が直接 apt で提供されています:
sudo apt-get update
sudo apt-get install -y swiftlang btrfs-progs libsqlite3-dev

# (Ubuntu 22.04 以前や他ディストリビューションの場合は Swift 公式パッケージを利用)
# curl -s https://archive.swiftlang.xyz/install.sh | sudo bash
# sudo apt-get install -y swiftlang btrfs-progs libsqlite3-dev

# ビルドとインストール (/usr/local/bin/clayfs)
./linux/build_linux.sh
```

> **Note**: `~/build/bin` に PATH が通っていることを確認してください（例: `export PATH="$HOME/build/bin:$PATH"`）。

---

## 💻 CLI 使い方 (Usage)

### 1. 新しい仮想ドライブを作成
```bash
# 64GB の仮想ドライブ「src」を作成
clayfs create src --size 64g
```

### 2. マウントと状態確認
```bash
# Finder にマウント (/Volumes/src に出現)
clayfs mount src

# マウント状態とドライブ一覧を表示
clayfs status
```

### 3. スナップショットの作成とタイムライン
```bash
# 即座にスナップショットを作成 (メッセージ付き)
clayfs snapshot src -m "大型リファクタリング直前"

# スナップショット履歴一覧
clayfs timeline src
```

### 4. 変更差分の確認と復元 (Restore)
```bash
# 現在の作業状態とスナップショットとの差分を表示
clayfs diff src

# 指定スナップショットの状態に瞬時に巻き戻す (全体復元)
clayfs restore src snap_20261108_052000

# 特定のファイル/ディレクトリのみ復元
clayfs restore src snap_20261108_052000 path/to/target.swift
```

### 5. 空き容量の回収 (Compaction)
```bash
# ファイル削除後にスパースバンドルの未使用ディスクブロックを回収
clayfs compact src
```

### 6. スナップショット履歴の整理 (Prune)
```bash
# 最大30件、直近14日以内のスナップショットを残して古い履歴を整理
clayfs prune src --keep 30 --days 14
```

### 7. 自動スナップショット監視 (Watch)
```bash
# 変更後5秒静穏で自動スナップショットを作成するデーモン
clayfs watch src
```

### 8. 起動設定 (Startup & Auto-mount)
```bash
# ログイン時の ClayFS 常駐アプリ自動起動を有効化/無効化
clayfs autostart on
clayfs autostart off

# 特定ドライブの起動時自動マウントを設定
clayfs automount src on
clayfs automount src off
```

### 9. 多言語ヘルプ
```bash
clayfs help                 # OSの言語設定に合わせて表示
clayfs help --lang en       # 英語で表示
clayfs help --lang ja       # 日本語で表示
```

---

## 🖥️ メニューバーアプリ (ClayFS.app)

ClayFS にはネイティブ SwiftUI 製のメニューバーアプリケーションが付属しています。

```bash
open ~/Applications/ClayFS.app
```

- **ステータスアイコン**: マウント状態やアクティビティをメニューバーに常時表示。
- **タイムラインビュー**: 過去のスナップショットを直感的なスライダーで選択。
- **クイックアクション**:
  - 📸 **Snapshot**: 1クリックで即座に保存
  - 🔄 **Compact**: ドライブの未使用領域を最適化
  - ⚙️ **Retention**: 最大件数・最大日数の保持ポリシーを設定＆即時整理
  - ⚙️ **Startup**: フッターの歯車アイコンからログイン時自動起動やドライブ自動マウントを一元管理
  - ⏱️ **Restore**: 変更ファイル数を確認して安全にロールバック

---

## 🏛️ アーキテクチャ (Architecture)

```
┌────────────────────────────────────────────────────────┐
│                      ClayFS                            │
├───────────────────────────┬────────────────────────────┤
│     ClayFS App (GUI)      │      ClayFS CLI (main)     │
│   SwiftUI / Menu Bar      │    Command Line Tool       │
├───────────────────────────┴────────────────────────────┤
│                   ClayFSCore Framework                 │
│  - StorageManager (APFS Sparsebundle / hdiutil / CoW)  │
│  - SnapshotManager (clonefile(2) / Diff / Prune)       │
│  - TimelineDB (SQLite3 WAL mode with busy_timeout)     │
│  - FSEventsMonitor (Low-overhead kernel event watch)   │
│  - DriveRegistry (flock cross-process atomic registry) │
│  - LaunchAtLogin (SMAppService & LaunchAgent)          │
│  - AppLocale (System language detection / 8 langs)     │
├────────────────────────────────────────────────────────┤
│                   macOS Kernel / APFS                  │
│       APFS Sparsebundle Image (Copy-on-Write)          │
└────────────────────────────────────────────────────────┘
```

- **APFS Sparsebundle**: 容量上限を指定しつつ、実使用分のみディスクを消費する動的バンドル形式。
- **SQLite3 WAL モード**: 先行書き込みログと `sqlite3_busy_timeout` による安全な同時アクセスと高速メタデータ管理。
- **Darwin FSEvents API**: カーネルレベルの低負荷なファイル変更通知を活用した自動監視。
- **flock(2) 排他制御**: CLI と常駐 GUI アプリ間の同時実行におけるアトミックな整合性保証。

---

## 🧪 テストの実行 (Testing)

ユニットテストおよび統合テスト（仮想ドライブの作成、マウント、スナップショット、復元、差分、回収、セキュリティ検査、破損保護）を実行します：

```bash
swift test
```

> - 仮想ドライブを作る統合テストは macOS の `hdiutil` が前提です。Linux ではその試験だけを飛ばし、
>   ユニットテスト（レジストリ、SQLite、CoW クローン、パス検査など）は実行します。
> - Linux 版（btrfs を使う `linux/clayfs_btrfs`）の試験は `linux/` にあります。
>   `linux/test_btrfs.sh`（root と btrfs が要る）に加え、btrfs なしで動く
>   `python3 linux/test_parse_dump.py` と `python3 linux/test_btrfs_logic.py` があります。

---

## 🐧 Linux 版ツール (btrfs)

リポジトリの `linux/` には、Swift 版とは別に、btrfs の subvolume を直接使う CLI があります
（設計は [docs/SPEC-linux-btrfs.md](docs/SPEC-linux-btrfs.md)）。

| ファイル | 役割 |
|---|---|
| `linux/clayfs_btrfs` | `work/` の subvolume と読み取り専用スナップショットで履歴を持つ CLI（Python） |
| `linux/install.sh` / `uninstall.sh` | 自動実行（毎時の `run`、毎日の `gc`、毎週の `scrub`）の導入と除去 |
| `linux/migrate_from_dir.sh` | 普通のフォルダの中身を `work/` へ移し、最初のコミットにする |
| `clayfs_tool` / `clayfsctl` | 以前の macOS 版（`make install-legacy` で旧 CLI として入る） |

---

## 📄 ライセンス (License)

MIT License
