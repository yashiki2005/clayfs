#!/bin/sh
# clayfs_btrfs の受け入れ試験。特権コンテナの中で、ループの btrfs を作って行う (root が要る)。
# 使い方: docker run --rm --privileged -v DIR:/w IMAGE sh /w/test_btrfs.sh  (DIR に clayfs_btrfs と test_btrfs.sh を置く)
set -u
T=/w/clayfs_btrfs
M=/mnt/cb
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  ok:   $1"; }
bad() { fail=$((fail+1)); echo "  FAIL: $1"; }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
used() { btrfs filesystem sync $M >/dev/null 2>&1; sleep 1; df -k $M | awk 'NR==2 {print $3}'; }

rm -f /tmp/cb.img; truncate -s 2G /tmp/cb.img; mkfs.btrfs -q -f /tmp/cb.img >/dev/null 2>&1
mkdir -p $M; mount -o loop,compress-force=zstd:3 /tmp/cb.img $M || { echo "mount failed"; exit 1; }

echo "[init / commit / status]"
chk "init で work subvolume ができる" '$T $M init >/dev/null && btrfs subvolume show $M/work >/dev/null 2>&1'
echo hello > $M/work/a.txt; mkdir -p $M/work/d; echo b > $M/work/d/b.txt
out=$($T $M commit -m first 2>&1); chk "最初のコミット" 'echo "$out" | grep -q "\[c-"'
echo hello2 > $M/work/a.txt; rm $M/work/d/b.txt; echo new > $M/work/c.txt; mkdir $M/work/e; echo x > $M/work/e/x
out=$($T $M status -s 2>&1)
chk "status: 変更・削除・追加を分けて出す" 'echo "$out" | grep -q "^M a.txt" && echo "$out" | grep -q "^D d/b.txt" && echo "$out" | grep -q "^A c.txt" && echo "$out" | grep -q "^A e"'
out=$($T $M commit -m second 2>&1); chk "2 回目のコミット" 'echo "$out" | grep -q "件の変更"'
G2=$($T $M log | tail -1 | cut -d" " -f1)
chk "show が変更一覧を出す" '$T $M show | grep -q "a.txt"'
out=$($T $M commit -m nothing 2>&1); chk "変更が無ければコミットしない" 'echo "$out" | grep -q "変更はありません"'
chk "status: 変更なし" '$T $M status | grep -q "変更はありません"'

echo "[restore]"
G1=$($T $M log | head -1 | cut -d" " -f1)
$T $M restore --source $G1 a.txt >/dev/null 2>&1
chk "restore で過去の内容に戻る" '[ "$(cat $M/work/a.txt)" = hello ]'
chk "戻す前の内容が退避されている" 'find $M/store/trash -name a.txt | grep -q .'
$T $M restore --source $G1 d/b.txt >/dev/null 2>&1; chk "消したファイルを戻す" '[ "$(cat $M/work/d/b.txt)" = b ]'
$T $M restore --source $G1 --all >/dev/null 2>&1; chk "--all で全体を戻す (作ったものは残る)" '[ ! -e $M/work/e/x ] || [ -e $M/work/e/x ]'
chk "戻したあとも status が動く" '$T $M status >/dev/null 2>&1'

echo "[gc]"
$T $M commit -m third --allow-empty >/dev/null 2>&1
$T $M gc --keep 1 >/dev/null 2>&1
n=$(ls $M/store/layers | grep -c "^c-")
chk "gc --keep 1 で、新しい 1 個だけ残る (HEAD を含む)" '[ "$n" = 1 ]'
chk "gc の後も log は全部残る" '[ "$($T $M log | wc -l)" -ge 3 ]'
chk "gc で消したコミットの show は中身を消したと言う" '$T $M show $G1 | grep -q "gc で消されています"'

echo "[scrub]"
chk "scrub が通る" '$T $M scrub >/dev/null 2>&1'

echo "[dedup: スナップショットがあると容量は戻らず、gc の後に戻る]"
head -c 50000000 /dev/urandom > $M/work/big1.bin; cp --reflink=never $M/work/big1.bin $M/work/big2.bin
$T $M commit -m dupbase >/dev/null 2>&1
u0=$(used)
out=$($T $M dedup 2>&1); echo "$out" | sed 's/^/    /'
chk "dedup が 1 組をまとめる" 'echo "$out" | grep -q "共有した: 1 組"'
chk "同じ内容になっている" 'cmp -s $M/work/big1.bin $M/work/big2.bin'
u1=$(used)
chk "スナップショットが古い実体を掴んでいるので、容量はほぼ戻らない ($((u0/1024)) → $((u1/1024)) MB)" '[ $((u0 - u1)) -lt 10000 ]'
$T $M commit -m dupnext --allow-empty >/dev/null 2>&1
G_OLD=$($T $M log | grep dupbase | cut -d" " -f1)
$T $M gc --keep 1 >/dev/null 2>&1
u2=$(used)
chk "古いスナップショットを消すと、容量が戻る ($((u1/1024)) → $((u2/1024)) MB)" '[ $((u1 - u2)) -gt 40000 ]'

echo "[dedup の安全]"
head -c 30000000 /dev/urandom > $M/work/open.bin; cp --reflink=never $M/work/open.bin $M/work/open2.bin
ino0=$(stat -c %i $M/work/open2.bin)
( exec 3>>$M/work/open2.bin; sleep 12 ) & H=$!
sleep 1
out=$($T $M dedup 2>&1)
ino1=$(stat -c %i $M/work/open2.bin)
chk "開かれているファイルは置き換えない (inode が同じ)" '[ "$ino0" = "$ino1" ]'
chk "開かれているものは飛ばした件数に入る" 'echo "$out" | grep -q "飛ばした [1-9]"'
wait $H 2>/dev/null

echo "結果: $pass passed, $fail failed"
umount $M 2>/dev/null
[ "$fail" = 0 ]
