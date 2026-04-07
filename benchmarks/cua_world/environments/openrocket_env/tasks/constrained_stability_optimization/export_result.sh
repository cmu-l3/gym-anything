#!/bin/bash
# Export script for constrained_stability_optimization task

echo "=== Exporting constrained_stability_optimization result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/task_final.png 2>/dev/null || true

SAVED_ORK="/home/ga/Documents/rockets/stable_swept_rocket.ork"
MEMO_FILE="/home/ga/Documents/exports/sweep_optimization_memo.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

ork_exists="false"
memo_exists="false"
ork_created_during_task="false"

if [ -f "$SAVED_ORK" ]; then
    ork_exists="true"
    ORK_MTIME=$(stat -c %Y "$SAVED_ORK" 2>/dev/null || echo "0")
    if [ "$ORK_MTIME" -gt "$TASK_START" ]; then
        ork_created_during_task="true"
    fi
fi

if [ -f "$MEMO_FILE" ]; then
    memo_exists="true"
fi

memo_size=0
[ -f "$MEMO_FILE" ] && memo_size=$(stat -c %s "$MEMO_FILE" 2>/dev/null)

# Save basic existence info for the verifier
write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_created_during_task\": $ork_created_during_task,
  \"memo_exists\": $memo_exists,
  \"memo_size\": $memo_size
}" /tmp/task_result.json

echo "=== Export complete ==="