#!/bin/bash
echo "=== Exporting competition_compliance_modification result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/compliance_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/compliance_check.ork"
MEMO_FILE="/home/ga/Documents/exports/compliance_memo.txt"

ork_exists="false"
memo_exists="false"
[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$MEMO_FILE" ] && memo_exists="true"

memo_size=0
[ -f "$MEMO_FILE" ] && memo_size=$(stat -c %s "$MEMO_FILE" 2>/dev/null)

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"memo_exists\": $memo_exists,
  \"memo_size\": $memo_size
}" /tmp/compliance_result.json

echo "=== Export complete ==="
