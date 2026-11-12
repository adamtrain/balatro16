#!/bin/sh
# Runs N copies of the stand-in game with the harness, on macOS or Linux.
#   dev/run_stub.sh <path-to-love-binary> [count] [test]
# With "test", instance 1 plays a scripted input sequence, every instance logs
# what its game received to $BM_LOG, and all of them quit after a few seconds.
set -e
LOVE="$1"
N="${2:-4}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export BM_MOD="$ROOT/mod/BalatroMulti/multi.lua"
export BM_LOG="${BM_LOG:-$ROOT/dev/logs}"
export BALATRO_MULTI_N="$N"
# The stand-in has no Steam library, so no instance may ask for the real one.
export BALATRO_MULTI_STEAM=0
[ "$3" = "test" ] && export BM_TEST=1
mkdir -p "$BM_LOG"
rm -f "$BM_LOG"/log_*.txt
i=1
while [ "$i" -le "$N" ]; do
    BALATRO_MULTI_ID="$i" "$LOVE" "$ROOT/dev/stubgame" &
    i=$((i + 1))
done
wait
