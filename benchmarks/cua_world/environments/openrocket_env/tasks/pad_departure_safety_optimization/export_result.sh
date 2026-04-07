#!/bin/bash
echo "=== Exporting pad_departure_safety_optimization result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/pad_safety_final.png 2>/dev/null || true

TARGET_ORK="/home/ga/Documents/rockets/safe_janus.ork"
MEMO_PATH="/home/ga/Documents/exports/pad_safety_memo.txt"

ork_exists="false"
memo_exists="false"
[ -f "$TARGET_ORK" ] && ork_exists="true"
[ -f "$MEMO_PATH" ] && memo_exists="true"

ork_size=0
memo_size=0
[ -f "$TARGET_ORK" ] && ork_size=$(stat -c %s "$TARGET_ORK" 2>/dev/null)
[ -f "$MEMO_PATH" ] && memo_size=$(stat -c %s "$MEMO_PATH" 2>/dev/null)

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_size\": $ork_size,
  \"memo_exists\": $memo_exists,
  \"memo_size\": $memo_size
}" /tmp/pad_safety_result.json

echo "=== Export complete ==="