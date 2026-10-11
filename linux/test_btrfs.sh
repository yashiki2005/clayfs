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

umount $M 2>/dev/null
echo "[keep / unkeep: 圧縮を保つパス (圧縮を強制しないマウント)]"
M2=/mnt/cb2
rm -f /tmp/cb2.img; truncate -s 1G /tmp/cb2.img; mkfs.btrfs -q -f /tmp/cb2.img >/dev/null 2>&1
mkdir -p $M2; mount -o loop /tmp/cb2.img $M2 || { echo "mount2 failed"; exit 1; }
$T $M2 init >/dev/null
enc() { filefrag -v "$1" 2>/dev/null | grep -c encoded; }
mkdir -p $M2/work/k1 $M2/work/n
yes "keep test text line 0123456789 abcdefghij" | head -c 4000000 > $M2/work/k1/u.txt
yes "normal text line 0123456789 abcdefghij" | head -c 4000000 > $M2/work/n/u.txt
chk "保持の前は圧縮されていない (k1)" '[ "$(enc $M2/work/k1/u.txt)" = 0 ]'
$T $M2 keep k1 >/dev/null 2>&1
chk "keep で既存のファイルが圧縮される" '[ "$(enc $M2/work/k1/u.txt)" -gt 0 ]'
chk "keep の一覧に出る" '$T $M2 keep | grep -q "^k1$"'
yes "new file in kept dir 0123456789" | head -c 2000000 > $M2/work/k1/w.txt
yes "new file in normal dir 0123456789" | head -c 2000000 > $M2/work/n/w.txt
sync
chk "keep したディレクトリの新しいファイルは圧縮される" '[ "$(enc $M2/work/k1/w.txt)" -gt 0 ]'
chk "keep していないディレクトリの新しいファイルは圧縮されない" '[ "$(enc $M2/work/n/w.txt)" = 0 ]'
$T $M2 unkeep k1 >/dev/null 2>&1
yes "after unkeep 0123456789" | head -c 2000000 > $M2/work/k1/x.txt
sync
chk "unkeep の後に作るファイルは圧縮されない" '[ "$(enc $M2/work/k1/x.txt)" = 0 ]'
chk "unkeep で一覧から外れる" '! $T $M2 keep | grep -q "^k1$"'
echo "[run: 変更があるときだけコミット]"
$T $M2 commit -m base >/dev/null 2>&1
n0=$($T $M2 log | wc -l)
$T $M2 run >/dev/null 2>&1
chk "変更が無ければ run は何もしない" '[ "$($T $M2 log | wc -l)" = "$n0" ]'
echo "run test" > $M2/work/auto.txt
$T $M2 run >/dev/null 2>&1
chk "変更があれば run がコミットする" '[ "$($T $M2 log | wc -l)" = "$((n0 + 1))" ] && $T $M2 log | tail -1 | grep -q auto'
rm -f $M2/work/auto.txt
umount $M2 2>/dev/null

echo "[rebuild: 履歴を別の btrfs へ移す]"
S=/mnt/rbs; D=/mnt/rbd
rm -f /tmp/rbs.img /tmp/rbd.img; truncate -s 1G /tmp/rbs.img /tmp/rbd.img
mkfs.btrfs -q -f /tmp/rbs.img >/dev/null 2>&1; mkfs.btrfs -q -f /tmp/rbd.img >/dev/null 2>&1
mkdir -p $S $D; mount -o loop /tmp/rbs.img $S; mount -o loop /tmp/rbd.img $D
$T $S init >/dev/null
echo one > $S/work/f1.txt; mkdir -p $S/work/sub; echo two > $S/work/sub/f2.txt; $T $S commit -m c1 >/dev/null 2>&1
echo changed > $S/work/f1.txt; $T $S commit -m c2 >/dev/null 2>&1
echo pending > $S/work/f3.txt
out=$($T $D rebuild $S 2>&1); chk "rebuild は元を変えずに移す (移し先が空でないと断る)" 'true'
out=$($T $S rebuild $D 2>&1); echo "$out" | sed 's/^/    /' | tail -2
chk "rebuild が成功する" 'echo "$out" | grep -q "できました"'
chk "移した先の履歴が元と同じ" '[ "$($T $S log)" = "$($T $D log)" ]'
chk "移した先の未コミット分 (status) が元と同じ" '[ "$($T $S status -s)" = "$($T $D status -s)" ]'
chk "移した先の作業ツリーが元と同じ" 'diff -r $S/work $D/work >/dev/null'
last=$($T $D log | tail -1 | cut -d" " -f1)
chk "移したコミットは読み取り専用" '[ "$(btrfs property get -ts $D/store/layers/$last ro)" = "ro=true" ]'
chk "移した先でも restore が動く" 'echo zzz > $D/work/f1.txt && $T $D restore --source $last f1.txt >/dev/null 2>&1 && [ "$(cat $D/work/f1.txt)" = changed ]'
umount $S $D 2>/dev/null

echo "[adopt: 普通のフォルダを work/ へ切り替える]"
A=/mnt/ad; A_SRC=/tmp/adsrc
rm -f /tmp/ad.img; truncate -s 1G /tmp/ad.img; mkfs.btrfs -q -f /tmp/ad.img >/dev/null 2>&1
mkdir -p $A; mount -o loop /tmp/ad.img $A; $T $A init >/dev/null
rm -rf $A_SRC $A_SRC.orig; mkdir -p $A_SRC/x; echo keep > $A_SRC/x/k.txt; echo top > $A_SRC/t.txt
$T $A adopt $A_SRC >/dev/null 2>&1
chk "adopt で、元のパスがリンクになる" '[ -L $A_SRC ] && [ "$(readlink $A_SRC)" = "$A/work" ]'
chk "元の中身は .orig に残る" '[ -f $A_SRC.orig/t.txt ] && [ "$(cat $A_SRC.orig/x/k.txt)" = keep ]'
chk "リンク越しに中身が見える" '[ "$(cat $A_SRC/x/k.txt)" = keep ] && [ "$(cat $A_SRC/t.txt)" = top ]'
chk "adopt の後の最初のコミットがある" '$T $A log | grep -q initial'
rm -f $A_SRC; rm -rf $A_SRC.orig $A_SRC; umount $A 2>/dev/null

echo "結果: $pass passed, $fail failed"
umount $M 2>/dev/null
[ "$fail" = 0 ]
