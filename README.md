# ClayFS 🏺

> **Next-Generation APFS Virtual Drive & Instant Time Machine for macOS**  
> macOS 向けの次世代 APFS 仮想ドライブ ＆ 超高速タイムマシン

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org)
[![APFS CoW](https://img.shields.io/badge/Filesystem-APFS%20CoW-blue)](https://developer.apple.com/documentation/foundation/filemanager)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

ClayFS は、macOS の **APFS Copy-on-Write (`clonefile(2)`)** を活用した、ストレージ消費ゼロで瞬時にスナップショットを作成・復元できる軽量仮想ドライブシステムです。

開発作業中の試行錯誤、巨大なコードベースの変更、Git コミット前の実験的リファクタリングなどを、Finder / CLI の境界なくいつでも自由自在に巻き戻すことができます。

---

## ✨ 主な特長 (Features)

1. **APFS CoW によるゼロコスト・スナップショット**
   - 変更があるまで追加ストレージを一切消費しない `clonefile(2)` によるミリ秒単位のスナップショット作成。
2. **Git 感覚のボリューム直接巻き戻し**
   - ドライブ（例: `/Volumes/src`）のルート全体を直感的にスナップショット＆ロールバック。
   - `.clayfs`、`.fseventsd`、`.Spotlight-V100` などのシステムディレクトリは自動除外され安全に保護。
3. **美しい常駐メニューバーアプリ (`ClayFS.app`)**
   - スライダーで直感的に時間をさかのぼれるタイムライン・スクラバー。
   - 変更ファイル数の可視化、1クリックでのロールバック確認シート、保持設定。
4. **シームレスな空き容量回収 (`compact`)**
   - ドライブ使用中に肥大化したスパースバンドルブロックを安全かつ瞬時に回収（同期 → 解除 → `hdiutil compact` → 再マウントを自動一括実行）。
5. **スナップショット保持ポリシー＆自動整理 (`prune`)**
   - 「最大保持件数」や「最大保持日数」を設定可能。スナップショット作成時にもバックグラウンドで自動プルーニング。
6. **FSEvents による自動監視 (`watch`)**
   - ファイル変更を監視し、指定時間の静穏（debounce）後に自動でスナップショットを生成。
7. **8言語のネイティブ多言語対応 (i18n)**
   - CLI および GUI ともに、macOS の主要 8 言語（日本語、英語、簡体字中国語、繁体字中国語、スペイン語、フランス語、ドイツ語、韓国語）に完全対応。OS の言語設定を自動検出します。

---

## 🚀 クイックスタート (Quick Start)

### 必須環境
- macOS 14.0 (Sonoma) 以降
- Xcode 16 または Command Line Tools (Swift 6.0)

### インストール (Build & Install)

```bash
git clone https://github.com/yourname/clayfs.git
cd clayfs

# ビルドおよびインストール (CLI: ~/build/bin/clayfs, GUI: ~/Applications/ClayFS.app)
make install
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

### 8. 多言語ヘルプ
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
│  - TimelineDB (SQLite3 WAL for instant metadata query) │
│  - FSEventsMonitor (Low-overhead kernel event watch)   │
│  - AppLocale (System language detection / 8 langs)     │
├────────────────────────────────────────────────────────┤
│                   macOS Kernel / APFS                  │
│       APFS Sparsebundle Image (Copy-on-Write)          │
└────────────────────────────────────────────────────────┘
```

- **APFS Sparsebundle**: 容量上限を指定しつつ、実使用分のみディスクを消費する動的バンドル形式。
- **SQLite3 WAL モード**: スナップショットのメタデータ、メッセージ、タイムスタンプを高速にクエリ・管理。
- **Darwin FSEvents API**: カーネルレベルの低負荷なファイル変更通知を活用した自動監視。

---

## 🧪 テストの実行 (Testing)

ユニットテストおよび統合テスト（仮想ドライブの作成、マウント、スナップショット、復元、差分、回収のエンドツーエンドテスト）を実行します：

```bash
swift test
```

---

## 📄 ライセンス (License)

MIT License
