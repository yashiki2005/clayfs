#!/bin/bash
# clayfsctl の鍵・オフライン作業の印・down・shrink の中断のテスト。使い捨てのイメージの中で動き、実際の設定には触れない。
# 使い方: bash experiments/test_ctl.sh
HERE="$(cd "$(dirname "$0")" && pwd -P)"
CTL="$HERE/../clayfsctl"
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  ok:   $1"; }
bad() { fail=$((fail+1)); echo "  FAIL: $1"; }
chk() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

T="$(mktemp -d /tmp/clayctl-test.XXXXXX)"; T="$(cd "$T" && pwd -P)"
export CLAYFS_DIR="$T/dir" CLAYFS_IMAGE="$T/img.sparsebundle" CLAYFS_MNT="$T/mnt" CLAYFS_COMMIT_INTERVAL=3600 CLAYFS_LOG="$T/log"
export CLAYFS_TOOL="$HERE/../clayfs_tool" SHRINK_MARGIN_KB=0
mkdir -p "$CLAYFS_DIR"; echo hello >"$CLAYFS_DIR/a.txt"
cleanup() {
  [ -n "${SLEEPER:-}" ] && kill "$SLEEPER" 2>/dev/null
  "$CTL" down --force >/dev/null 2>&1
  hdiutil detach -force "$CLAYFS_MNT" >/dev/null 2>&1
  rm -rf "${T:?}"
}
trap cleanup EXIT
"$CTL" init 2g >/dev/null 2>&1 || { echo "init 失敗"; exit 1; }
"$CTL" up >/dev/null 2>&1 || { echo "up 失敗"; exit 1; }
procid() { printf '%s %s' "$1" "$(ps -o lstart= -p "$1" 2>/dev/null | tr ' ' '_')"; }
sleep 600 & SLEEPER=$!

echo "[鍵]"
ln -s "$(procid $SLEEPER)" "$CLAYFS_MNT/store/lock"
out="$("$CTL" commit -m x 2>&1)"; rc=$?
chk "生きた持ち主の鍵があれば、commit は断る" '[ $rc != 0 ] && echo "$out" | grep -q "実行中"'
chk "断ったあとも、他人の鍵は消えない" '[ -L "$CLAYFS_MNT/store/lock" ]'
rm -f "$CLAYFS_MNT/store/lock"
ln -s "99999 Mon_Jan__1_00:00:00_2001" "$CLAYFS_MNT/store/lock"
out="$("$CTL" commit -m y 2>&1)"; rc=$?
chk "持ち主がいない鍵は引き取る" '[ $rc = 0 ]'
chk "終わったら鍵が残らない" '[ ! -e "$CLAYFS_MNT/store/lock" ] && [ ! -L "$CLAYFS_MNT/store/lock" ]'
ln -s "$SLEEPER Mon_Jan__1_00:00:00_2001" "$CLAYFS_MNT/store/lock"      # PID は生きているが、開始時刻が違う (PID の再利用)
out="$("$CTL" commit -m z 2>&1)"; rc=$?
chk "PID が再利用されていても、別のプロセスなら鍵を引き取る" '[ $rc = 0 ]'
rm -f "$CLAYFS_MNT/store/lock"
# 同時に引き取り合っても、全部が成功するか、断られるかで、壊れない
ln -s "99999 Mon_Jan__1_00:00:00_2001" "$CLAYFS_MNT/store/lock"
for i in 1 2 3 4; do ( "$CTL" status >/dev/null 2>&1; "$CTL" gc --keep 50 >"$T/gc.$i" 2>&1; echo $? >"$T/gc.rc.$i" ) & done; wait $(jobs -p | grep -v "^$SLEEPER$") 2>/dev/null
n=0; for i in 1 2 3 4; do [ "$(cat "$T/gc.rc.$i" 2>/dev/null)" = 0 ] && n=$((n+1)); done
chk "古い鍵を同時に引き取ろうとしても、1 つ以上が成功し、鍵が残らない ($n/4 成功)" '[ $n -ge 1 ] && [ ! -e "$CLAYFS_MNT/store/lock" ] && [ ! -L "$CLAYFS_MNT/store/lock" ]'

echo "[down]"
ln -s "$(procid $SLEEPER)" "$CLAYFS_MNT/store/lock"
out="$("$CTL" down --force 2>&1)"; rc=$?
chk "他の clayfsctl が実行中なら、down --force でも外さない" '[ $rc != 0 ] && [ -d "$CLAYFS_MNT/work" ]'
rm -f "$CLAYFS_MNT/store/lock"

echo "[オフライン作業の印]"
"$CTL" down >/dev/null 2>&1
chk "外せた" '[ ! -d "$CLAYFS_MNT/work" ]'
mkdir "$CLAYFS_MNT.offline"; procid $SLEEPER >"$CLAYFS_MNT.offline/owner"
out="$("$CTL" up 2>&1)"; rc=$?
chk "オフライン作業中は up がマウントしない" '[ $rc != 0 ] && echo "$out" | grep -q "オフライン作業中" && [ ! -d "$CLAYFS_MNT/work" ]'
out="$("$CTL" run 2>&1)"; rc=$?
chk "run は何もせず成功で終わる (launchd が失敗として扱わない)" '[ $rc = 0 ] && [ ! -d "$CLAYFS_MNT/work" ]'
out="$("$CTL" exec true 2>&1)"; rc=$?
chk "exec もマウントしない" '[ $rc != 0 ] && [ ! -d "$CLAYFS_MNT/work" ]'
rm -rf "$CLAYFS_MNT.offline"; mkdir "$CLAYFS_MNT.offline"; echo "99999 Mon_Jan__1_00:00:00_2001" >"$CLAYFS_MNT.offline/owner"
"$CTL" up >/dev/null 2>&1
chk "持ち主のいない印は無視してマウントする" '[ -d "$CLAYFS_MNT/work" ] && [ ! -d "$CLAYFS_MNT.offline" ]'

echo "[shrink の中断]"
# 空きをゼロで埋めている最中に止める。止めたあと、ゼロ埋めのファイルが残らず、再マウントされる
( "$CTL" shrink >"$T/shrink.log" 2>&1 ) & SH=$!
for i in $(seq 1 100); do ls "$HOME"/.clayfs-shrink.*/.clayfs-zerofill >/dev/null 2>&1 && break; sleep 0.2; done
chk "ゼロ埋めの最中に始まった" 'ls "$HOME"/.clayfs-shrink.*/.clayfs-zerofill >/dev/null 2>&1'
out="$("$CTL" up 2>&1)"; rc=$?
chk "shrink の間は up を断る" '[ $rc != 0 ] && echo "$out" | grep -q "オフライン作業中"'
SHPID="$(pgrep -f "clayfsctl shrink" | head -1)"
kill -TERM $SHPID 2>/dev/null; wait $SH 2>/dev/null
for i in $(seq 1 100); do [ -d "$CLAYFS_MNT/work" ] && break; sleep 0.3; done
chk "中断のあと、再マウントされている" '[ -d "$CLAYFS_MNT/work" ]'
chk "ゼロ埋めのファイルがイメージに残らない" '[ ! -e "$CLAYFS_MNT/.clayfs-zerofill" ] && [ -z "$(ls -A "$HOME"/.clayfs-shrink.* 2>/dev/null)" ]'
free_kb="$(df -k "$CLAYFS_MNT" | tail -1 | awk '{print $4}')"
chk "ボリュームの空きが戻っている (${free_kb} KB)" '[ "$free_kb" -gt 500000 ]'
chk "印と鍵が残らない" '[ ! -d "$CLAYFS_MNT.offline" ] && [ ! -e "$CLAYFS_MNT/store/lock" ] && [ ! -L "$CLAYFS_MNT/store/lock" ]'

echo "[run: 古い版の自動検査]"
export CLAYFS_ALLOW_BATTERY=1
W="$CLAYFS_MNT/work"
head -c 200000 /dev/urandom >"$W/v.bin"; "$CTL" commit -m s1 >/dev/null 2>&1
sleep 1.2; head -c 200000 /dev/urandom >"$W/v.bin"; "$CTL" commit -m s2 >/dev/null 2>&1
"$CTL" scrub >/dev/null 2>&1                      # 索引を作る
out="$("$CTL" run 2>&1)"; rc=$?
chk "索引ができていれば、run が古い版を検査する" '[ $rc = 0 ] && echo "$out" | grep -q "コミットの古い版を検査" && [ -f "$CLAYFS_MNT/store/layers-scrub.last" ]'
out="$("$CTL" run 2>&1)"
chk "間隔が空くまでは、もう一度検査しない" '! echo "$out" | grep -q "コミットの古い版を検査"'
L1=""; for n in $(ls "$CLAYFS_MNT/store/layers" | grep -v '^\.'); do [ -f "$CLAYFS_MNT/store/layers/$n/fs/v.bin" ] && { L1="$n"; break; }; done
s_=$(stat -f %m "$CLAYFS_MNT/store/layers/$L1/fs/v.bin")
printf 'CORRUPT' | dd of="$CLAYFS_MNT/store/layers/$L1/fs/v.bin" bs=1 seek=500 conv=notrunc 2>/dev/null
touch -t 200001010000 "$CLAYFS_MNT/store/layers-scrub.last"
python3 - "$CLAYFS_MNT/store/layers/$L1/fs/v.bin" "$s_" <<'PY'
import os,sys; p=sys.argv[1]; st=os.stat(p); os.utime(p, ns=(st.st_atime_ns, int(sys.argv[2])*10**9 + (st.st_mtime_ns % 10**9)))
PY
out="$("$CTL" run 2>&1)"; rc=$?
chk "壊れた版があっても run は成功し、警告と印を残す" '[ $rc = 0 ] && echo "$out" | grep -q "壊れた版" && [ -f "$CLAYFS_MNT/store/layers-scrub.broken" ]'
unset CLAYFS_ALLOW_BATTERY

echo "結果: $pass passed, $fail failed"
[ "$fail" = 0 ]
