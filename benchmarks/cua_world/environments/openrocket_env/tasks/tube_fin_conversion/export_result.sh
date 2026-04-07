#!/bin/bash
echo "=== Exporting tube_fin_conversion result ==="
source /workspace/scripts/task_utils.sh || exit 1

# Take final screenshot
take_screenshot /tmp/tube_fin_final.png 2>/dev/null || true

# Read baseline info
TASK_START=$(cat /tmp/task_start_ts.txt 2>/dev/null || echo "0")
SOURCE_MD5=$(cat /tmp/source_ork_md5.txt 2>/dev/null || echo "")

# Expected output paths
TARGET_ORK="/home/ga/Documents/rockets/tube_fin_conversion.ork"
REPORT_MD="/home/ga/Documents/exports/tube_fin_report.md"
REPORT_TXT="/home/ga/Documents/exports/tube_fin_report.txt"

ork_exists="false"
ork_mtime=0
ork_md5=""

if [ -f "$TARGET_ORK" ]; then
    ork_exists="true"
    ork_mtime=$(stat -c %Y "$TARGET_ORK" 2>/dev/null)
    ork_md5=$(md5sum "$TARGET_ORK" | awk '{print $1}')
fi

report_path=""
report_exists="false"
report_mtime=0
report_size=0

if [ -f "$REPORT_MD" ]; then
    report_path="$REPORT_MD"
    report_exists="true"
    report_mtime=$(stat -c %Y "$REPORT_MD" 2>/dev/null)
    report_size=$(stat -c %s "$REPORT_MD" 2>/dev/null)
elif [ -f "$REPORT_TXT" ]; then
    report_path="$REPORT_TXT"
    report_exists="true"
    report_mtime=$(stat -c %Y "$REPORT_TXT" 2>/dev/null)
    report_size=$(stat -c %s "$REPORT_TXT" 2>/dev/null)
fi

write_result_json "{
  \"task_start_ts\": $TASK_START,
  \"source_ork_md5\": \"$SOURCE_MD5\",
  \"ork_exists\": $ork_exists,
  \"ork_mtime\": $ork_mtime,
  \"ork_md5\": \"$ork_md5\",
  \"report_exists\": $report_exists,
  \"report_path\": \"$report_path\",
  \"report_mtime\": $report_mtime,
  \"report_size\": $report_size
}" /tmp/tube_fin_result.json

echo "=== Export complete ==="