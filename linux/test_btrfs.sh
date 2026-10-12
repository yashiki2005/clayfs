#!/bin/sh
# clayfs_btrfs の受け入れ試験。特権コンテナの中で、ループの btrfs を作って行う (root が要る)。
# 使い方: docker run --rm --privileged -v DIR:/w IMAGE sh /w/test_btrfs.sh  (DIR に clayfs_btrfs と test_btrfs.sh を置く)
set -u
T=/w/clayfs_btrfs
M=/mnt/cb
pass=0; fail=0
# loop 装置は、ホスト全体で数が限られる (Pi では snap のイメージで埋まりやすい)。足りないと、試験の途中で
# mount が失敗して、ツールの不具合に見えてしまう。先に数えて、足りなければ理由を出して止まる
need=3
free=$(losetup -f >/dev/null 2>&1 && losetup -l 2>/dev/null | wc -l)
if ! (losetup -f >/dev/null 2>&1) ; then echo "環境: 空きの loop 装置がありません。snap や試験用のマウントを外してから実行してください"; exit 2; fi
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
$T $M commit -m base2 >/dev/null 2>&1
cat $M/work/a.txt >/dev/null; sleep 1
chk "読むだけ (atime の変化) は変更にならない" '[ -z "$($T $M status -s)" ]'
touch -m -d "2030-01-01 00:00" $M/work/a.txt
chk "mtime を変えただけのものは変更になる" '$T $M status -s | grep -q "^M a.txt"'
$T $M commit -m base3 >/dev/null 2>&1
head -c 300000 /dev/urandom > $M/work/same.bin; sync; $T $M commit -m base4 >/dev/null 2>&1
cp -p $M/work/same.bin /tmp/same.copy; cp -p /tmp/same.copy $M/work/same.bin; sync; sleep 1  # 時刻を保つ (時刻が変われば、それ自体は変更として数える)
chk "同じ中身に書き直したものは変更にならない" '! $T $M status -s | grep -q "same.bin"'
printf 'X' | dd of=$M/work/same.bin bs=1 seek=100 conv=notrunc 2>/dev/null; sync
chk "中身を変えたものは変更になる" '$T $M status -s | grep -q "^M same.bin"'
$T $M commit -m base5 >/dev/null 2>&1
cd $M/work; mkdir -p "odd d"; echo a > "odd d/x y.sql"; echo b > "a  b.txt"; echo k > oldname.txt
$T $M commit -m odd >/dev/null 2>&1
echo more > "odd d/x y.sql"; mv oldname.txt "new name.txt"; echo z > "a  b.txt"; sync; sleep 1
st=$($T $M status -s); cd /
chk "空白を含む名前の変更を、正しい名前で出す (M)" 'echo "$st" | grep -Fx "M odd d/x y.sql" >/dev/null && echo "$st" | grep -Fx "M a  b.txt" >/dev/null'
chk "名前の変更 (link と unlink) を、新しい名前の追加と、古い名前の削除で出す" 'echo "$st" | grep -Fx "A new name.txt" >/dev/null && echo "$st" | grep -Fx "D oldname.txt" >/dev/null'
$T $M commit -m odd2 >/dev/null 2>&1
echo "[exclude: フォルダ名で除外 (すぐ効く)]"
mkdir -p $M/work/.venv/lib; echo v1 > $M/work/.venv/lib/x.py; echo keep > $M/work/keep.txt; $T $M commit -m preex >/dev/null 2>&1
$T $M exclude .venv >/dev/null
chk "exclude の一覧に出る" '$T $M exclude | grep -qx .venv'
echo v2 > $M/work/.venv/lib/x.py; echo n > $M/work/keep.txt; sync; sleep 1
st=$($T $M status -s)
chk "除外したフォルダの変更は出ない" '! echo "$st" | grep -q "\.venv"'
chk "除外していないものの変更は出る" 'echo "$st" | grep -qx "M keep.txt"'
$T $M commit -m exclude-test >/dev/null 2>&1
chk "コミットの記録にも、除外したものは入らない" '! $T $M show | grep -q "\.venv"'
$T $M exclude --remove .venv >/dev/null
echo v3 > $M/work/.venv/lib/x.py; sync; sleep 1
chk "除外から外すと、変更が出る" '$T $M status -s | grep -q "\.venv"'
chk "一覧が空に戻る" '[ -z "$($T $M exclude)" ] || $T $M exclude | grep -q "(なし)" || true'

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

echo "[migrate: 普通のフォルダから移す]"
G=/mnt/mg
rm -f /tmp/mg.img; truncate -s 1G /tmp/mg.img; mkfs.btrfs -q -f /tmp/mg.img >/dev/null 2>&1
mkdir -p $G; mount -o loop /tmp/mg.img $G; $T $G init >/dev/null
MS=/tmp/mgsrc; rm -rf $MS; mkdir -p $MS/Documents/a/b $MS/empty; echo one > $MS/Documents/a/f.txt; echo two > $MS/Documents/a/b/g.txt
chmod 640 $MS/Documents/a/f.txt; touch -d '2020-01-02 03:04:05' $MS/Documents/a/f.txt
out=$(sh /w/migrate_from_dir.sh $MS $G $T 2>&1); echo "$out" | sed 's/^/    /' | tail -2
chk "移行が成功する" 'echo "$out" | grep -q "完了"'
chk "中身が同じ" 'diff -r $MS/Documents $G/work/Documents >/dev/null'
chk "権限と時刻が保たれる" '[ "$(stat -c %a $G/work/Documents/a/f.txt)" = 640 ] && [ "$(stat -c %Y $G/work/Documents/a/f.txt)" = "$(stat -c %Y $MS/Documents/a/f.txt)" ]'
chk "空のディレクトリも移る" '[ -d $G/work/empty ]'
chk "移行が最初のコミットになる" '$T $G log | grep -q "移行"'
chk "元は残る" '[ -f $MS/Documents/a/f.txt ]'
umount $G 2>/dev/null

echo "[create: イメージを作って、フォーマットし、マウントし、init まで]"
CR=/mnt/cr; CRI=/tmp/cr-test.img
rm -f $CRI; umount $CR 2>/dev/null; rm -rf $CR
chk "dry-run は何も作らない" '$T create 1G --image $CRI --mnt $CR --dry-run >/dev/null && [ ! -e $CRI ]'
$T create 1G --image $CRI --mnt $CR >/dev/null 2>&1
chk "create が、イメージとマウントと work/ を作る" '[ -f $CRI ] && mountpoint -q $CR && btrfs subvolume show $CR/work >/dev/null 2>&1'
chk "info が書く場所 (work) を示す" '$T $CR info | grep -q "書く場所.*$CR/work"'
LK=/tmp/lk-test/src
rm -rf /tmp/lk-test; $T $CR link $LK --owner nobody >/dev/null 2>&1
chk "link で、書く場所 (~/src 相当) が work/ へのリンクになる" '[ -L $LK ] && [ "$(readlink $LK)" = "$CR/work" ]'
chk "リンク越しに書くと、work/ に入る" 'echo hi > $LK/via-link.txt && [ "$(cat $CR/work/via-link.txt)" = hi ]'
chk "--owner で work/ の持ち主が変わる (nobody)" '[ "$(stat -c %U $CR/work)" = nobody ]'
out=$($T $CR link $LK 2>&1); chk "既にある名前には張らない" 'echo "$out" | grep -q "すでにあります"'
rm -f $CR/work/via-link.txt; rm -f $LK; rm -rf /tmp/lk-test
chk "info が履歴の場所を示す" '$T $CR info | grep -q "履歴の保存先.*store/layers"'
chk "create は btrfs の圧縮オプションでマウントする" 'mount | grep " $CR " | grep -q compress-force'
out=$($T create 1G --image $CRI --mnt $CR 2>&1); chk "既存のイメージは作り直さない" 'echo "$out" | grep -q "すでにあります"'
umount $CR; rm -f $CRI
mkdir -p $CR; echo x > $CR/junk
out=$($T create 1G --image $CRI --mnt $CR 2>&1); chk "空でないマウント先は使わない" 'echo "$out" | grep -q "空ではありません" && [ ! -e $CRI ]'
rm -rf $CR

echo "[任意の場所: 隠しフォルダや空白を含むパスでも動く]"
AM="/mnt/any dir/.clayfs-x"; AI="/tmp/any dir/x.img"; AL="/tmp/home dir/.src/src"
rm -rf "/mnt/any dir" "/tmp/any dir" "/tmp/home dir"
$T create 1G --image "$AI" --mnt "$AM" --link "$AL" >/dev/null 2>&1
chk "空白と隠しフォルダを含むマウント先に作れる" 'mountpoint -q "$AM" && btrfs subvolume show "$AM/work" >/dev/null 2>&1'
chk "空白を含むリンク先 (書く場所) が work/ を指す" '[ -L "$AL" ] && [ "$(readlink "$AL")" = "$AM/work" ]'
chk "リンク越しに書ける" 'echo ok > "$AL/a b.txt" && [ "$(cat "$AM/work/a b.txt")" = ok ]'
$T "$AM" commit -m spaces >/dev/null 2>&1; chk "空白を含むマウント先でコミットできる" '$T "$AM" log | grep -q spaces'
umount "$AM"; rm -rf "/mnt/any dir" "/tmp/any dir" "/tmp/home dir"

echo "結果: $pass passed, $fail failed"
umount $M 2>/dev/null
[ "$fail" = 0 ]
