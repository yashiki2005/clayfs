#!/usr/bin/env bash
set -euo pipefail

echo "=== ClayFS v2 CLI - Linux Build & Install ==="

# Check swift compiler
if ! command -v swift &> /dev/null; then
    echo "エラー: Swift コンパイラが見つかりません。Swift 6.0 以上をインストールしてください。"
    echo ""
    echo "【インストール方法 (Ubuntu / Debian)】"
    echo "  Ubuntu 24.04+: sudo apt-get update && sudo apt-get install -y swiftlang"
    echo "  または公式リポジトリ:"
    echo "    curl -s https://archive.swiftlang.xyz/install.sh | sudo bash"
    echo "    sudo apt-get install -y swiftlang"
    echo ""
    echo "【その他ディストリビューション】"
    echo "  公式ガイド: https://www.swift.org/install/linux/"
    exit 1
fi

echo "Swift バージョン: $(swift --version | head -n 1)"

# Check btrfs-progs
if ! command -v mkfs.btrfs &> /dev/null; then
    echo "警告: 'mkfs.btrfs' が見つかりません。btrfs-progs (btrfs-tools) をインストールしてください:"
    echo "  Ubuntu/Debian: sudo apt-get install -y btrfs-progs libsqlite3-dev"
    echo "  Fedora/RHEL:   sudo dnf install -y btrfs-progs sqlite-devel"
    echo "  Arch Linux:    sudo pacman -S btrfs-progs sqlite"
fi

echo "ClayFS CLI をビルド中 (Release モード)..."
swift build -c release --product clayfs

BUILD_BIN=".build/release/clayfs"
if [ ! -f "$BUILD_BIN" ]; then
    echo "エラー: ビルドバイナリが見つかりません: $BUILD_BIN"
    exit 1
fi

echo "ビルド成功: $BUILD_BIN"

INSTALL_DIR="/usr/local/bin"
if [ -w "$INSTALL_DIR" ]; then
    cp "$BUILD_BIN" "$INSTALL_DIR/clayfs"
    echo "インストール完了: $INSTALL_DIR/clayfs"
else
    echo "sudo で $INSTALL_DIR にインストールします..."
    sudo cp "$BUILD_BIN" "$INSTALL_DIR/clayfs"
    echo "インストール完了: $INSTALL_DIR/clayfs"
fi

echo ""
echo "=== 動作確認 ==="
clayfs --version
echo ""
echo "ClayFS v2 CLI が正常にインストールされました！"
echo "使い方: clayfs help"
