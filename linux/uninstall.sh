#!/bin/sh
# clayfs (btrfs) の自動実行を外す。データ (btrfs の中身と履歴) と /etc/clayfs-btrfs.env は残す。
# 使い方: sudo ./uninstall.sh [--dry-run]
set -eu
DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; fi
run() { if [ "$DRY" = 1 ]; then echo "+ $*"; else "$@"; fi; }
[ "$DRY" = 1 ] || [ "$(id -u)" = 0 ] || { echo "root で実行してください" >&2; exit 1; }
run systemctl disable --now clayfs-btrfs-run.timer clayfs-btrfs-gc.timer clayfs-btrfs-scrub.timer 2>/dev/null || true
for u in clayfs-btrfs-run.service clayfs-btrfs-run.timer clayfs-btrfs-gc.service clayfs-btrfs-gc.timer clayfs-btrfs-scrub.service clayfs-btrfs-scrub.timer; do
  run rm -f "/etc/systemd/system/$u"
done
run systemctl daemon-reload
run rm -f /usr/local/bin/clayfs_btrfs
echo "外しました。データと /etc/clayfs-btrfs.env は残しています"
