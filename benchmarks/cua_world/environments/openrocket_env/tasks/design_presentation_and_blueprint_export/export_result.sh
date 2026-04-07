#!/bin/bash
echo "=== Exporting design_presentation_and_blueprint_export result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/cdr_task_final.png 2>/dev/null || true

TASK_START=$(cat /tmp/cdr_task_start.txt 2>/dev/null || echo "0")

ORK_FILE="/home/ga/Documents/rockets/cdr_rocket.ork"
DR_FILE="/home/ga/Documents/exports/design_report.pdf"
FA_FILE="/home/ga/Documents/exports/fin_alignment_guide.pdf"

ork_exists="false"
dr_exists="false"
fa_exists="false"

[ -f "$ORK_FILE" ] && ork_exists="true"
[ -f "$DR_FILE" ] && dr_exists="true"
[ -f "$FA_FILE" ] && fa_exists="true"

ork_size=0
dr_size=0
fa_size=0

[ -f "$ORK_FILE" ] && ork_size=$(stat -c %s "$ORK_FILE" 2>/dev/null)
[ -f "$DR_FILE" ] && dr_size=$(stat -c %s "$DR_FILE" 2>/dev/null)
[ -f "$FA_FILE" ] && fa_size=$(stat -c %s "$FA_FILE" 2>/dev/null)

dr_mtime=0
fa_mtime=0
[ -f "$DR_FILE" ] && dr_mtime=$(stat -c %Y "$DR_FILE" 2>/dev/null)
[ -f "$FA_FILE" ] && fa_mtime=$(stat -c %Y "$FA_FILE" 2>/dev/null)

# Prepare JSON output safely
TEMP_JSON=$(mktemp /tmp/cdr_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start_ts": $TASK_START,
  "ork_exists": $ork_exists,
  "ork_size": $ork_size,
  "dr_exists": $dr_exists,
  "dr_size": $dr_size,
  "dr_mtime": $dr_mtime,
  "fa_exists": $fa_exists,
  "fa_size": $fa_size,
  "fa_mtime": $fa_mtime
}
EOF

# Write result using utility to handle permissions properly
write_result_json "$(cat $TEMP_JSON)" /tmp/cdr_task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="