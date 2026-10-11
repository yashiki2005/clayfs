#!/bin/sh
# 普通のフォルダ (例 ~/cfs のマウント) の中身を、btrfs の work/ へ移し、最初のコミットにする。元は読むだけで、消さない。
# 使い方: sudo ./migrate_from_dir.sh SRC MNT TOOL
#   SRC  移す元 (例 /home/yy/cfs)。lost+found は除く
#   MNT  clayfs の btrfs のマウント先 (例 /srv/clayfs)。work/ が空であること
#   TOOL clayfs_btrfs の場所
set -eu
SRC="${1:?使い方: sudo ./migrate_from_dir.sh SRC MNT TOOL}"
MNT="${2:?MNT}"
TOOL="${3:?TOOL}"
[ "$(id -u)" = 0 ] || { echo "root で実行してください (所有者を保つため)" >&2; exit 1; }
[ -d "$SRC" ] || { echo "元がありません: $SRC" >&2; exit 1; }
[ -z "$(ls -A "$MNT/work")" ] || { echo "work/ が空ではありません: $MNT/work" >&2; exit 1; }

snap() { # 所有者・権限・大きさ・更新時刻・中身を並べる (中身はハッシュで比べる)
  # 一番上 (.) は除く: 移し先の work/ 自身の時刻は、中身を入れるたびに変わる。
  # ディレクトリの大きさは、ファイルシステムごとに違う値なので比べない (ファイルだけ大きさを比べる)
  (cd "$1" && {
    find . -mindepth 1 -path ./lost+found -prune -o -type d -print0 | xargs -0 -r stat -c '%n %U %G %a dir %Y'
    find . -mindepth 1 -path ./lost+found -prune -o -type f -print0 | xargs -0 -r stat -c '%n %U %G %a file %s %Y'
  } | sort)
}

echo "[1] 複製する (reflink ではなく、実体のコピー。所有者・時刻・属性を保つ)"
for n in $(ls -A "$SRC" | grep -v '^lost+found$'); do
  cp -a --reflink=never "$SRC/$n" "$MNT/work/"
done

echo "[2] 中身と、メタデータ (所有者・権限・大きさ・時刻) が一致するか確かめる"
(cd "$SRC" && find . -path ./lost+found -prune -o -type f -print0 | sort -z | xargs -0 sha256sum > /tmp/clayfs-migrate-src.sha)
(cd "$MNT/work" && find . -type f -print0 | sort -z | xargs -0 sha256sum > /tmp/clayfs-migrate-dst.sha)
if ! diff -q /tmp/clayfs-migrate-src.sha /tmp/clayfs-migrate-dst.sha >/dev/null; then
  echo "中身が一致しません。元は変えていません:" >&2; diff /tmp/clayfs-migrate-src.sha /tmp/clayfs-migrate-dst.sha | head -20 >&2; exit 1
fi
snap "$SRC" > /tmp/clayfs-migrate-src.meta
snap "$MNT/work" > /tmp/clayfs-migrate-dst.meta
if ! diff -q /tmp/clayfs-migrate-src.meta /tmp/clayfs-migrate-dst.meta >/dev/null; then
  echo "メタデータが一致しません (所有者・権限・時刻のいずれか):" >&2; diff /tmp/clayfs-migrate-src.meta /tmp/clayfs-migrate-dst.meta | head -20 >&2; exit 1
fi
rm -f /tmp/clayfs-migrate-*.sha /tmp/clayfs-migrate-*.meta

echo "[3] 最初のコミットを作る"
"$TOOL" "$MNT" commit -m "移行: $SRC から"
echo "完了。元の $SRC は残しています (確かめたら、cfs 側は別に外します)"
