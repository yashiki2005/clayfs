#!/bin/sh
# clayfs (btrfs) を Linux に入れる。root が要る (/usr/local/bin、/etc、systemd のため)。
# 使い方: sudo ./install.sh MNT [KEEP]
#   MNT   btrfs のマウント先 (絶対パス。init 済みであること。例 /srv/clayfs、/home/yy/.src.clayfs)
#   KEEP  残す世代の数 (既定 168)
# --dry-run を付けると、実行するコマンドを表示するだけで、何も変えない (root は要らない)。
set -eu
DRY=0
if [ "${1:-}" = "--dry-run" ]; then DRY=1; shift; fi
MNT="${1:?使い方: sudo ./install.sh MNT [KEEP]}"
case "$MNT" in /*) ;; *) echo "MNT は絶対パスで指定してください: $MNT" >&2; exit 1 ;; esac
KEEP="${2:-168}"
HERE="$(cd "$(dirname "$0")" && pwd -P)"
TOOL="$HERE/clayfs_btrfs"
UNITS="$HERE/systemd"
ENV=/etc/clayfs-btrfs.env

run() { if [ "$DRY" = 1 ]; then echo "+ $*"; else "$@"; fi; }

[ "$DRY" = 1 ] || [ "$(id -u)" = 0 ] || { echo "root で実行してください (sudo ./install.sh ...)" >&2; exit 1; }
case "$KEEP" in ''|*[!0-9]*) echo "KEEP は整数で指定してください: $KEEP" >&2; exit 1 ;; esac
[ "$KEEP" -ge 1 ] || { echo "KEEP は 1 以上にしてください" >&2; exit 1; }
[ -f "$TOOL" ] || { echo "見つかりません: $TOOL" >&2; exit 1; }
if [ "$DRY" = 0 ]; then
  findmnt -n -o FSTYPE -T "$MNT" 2>/dev/null | grep -qx btrfs || { echo "$MNT が btrfs ではありません (先にマウントし、init してください)" >&2; exit 1; }
fi

echo "[1] ツールを入れる"
run install -m 0755 "$TOOL" /usr/local/bin/clayfs_btrfs

echo "[2] 設定ファイル (既にあれば残す)"
if [ "$DRY" = 1 ] || [ ! -e "$ENV" ]; then
  if [ "$DRY" = 1 ]; then
    echo "+ write $ENV (CLAYFS_MNT=$MNT CLAYFS_KEEP=$KEEP)"
  else
    printf 'CLAYFS_MNT=%s\nCLAYFS_KEEP=%s\n' "$MNT" "$KEEP" > "$ENV"
    chmod 0644 "$ENV"
  fi
else
  echo "既にあります: $ENV (変更しません)"
fi

echo "[3] systemd のユニット"
for u in clayfs-btrfs-run.service clayfs-btrfs-run.timer clayfs-btrfs-gc.service clayfs-btrfs-gc.timer clayfs-btrfs-scrub.service clayfs-btrfs-scrub.timer; do
  run install -m 0644 "$UNITS/$u" "/etc/systemd/system/$u"
done
run systemctl daemon-reload

echo "[4] タイマーを有効にする (毎時の run、毎日の gc、毎週の scrub)"
run systemctl enable --now clayfs-btrfs-run.timer clayfs-btrfs-gc.timer clayfs-btrfs-scrub.timer

echo "完了。確認: systemctl list-timers 'clayfs-btrfs-*'"
