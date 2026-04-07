#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

RESULTS_DIR="/home/ga/UGENE_Data/proteomics_results"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check GB file
GB_FILE="${RESULTS_DIR}/hbb_trypsin_annotated.gb"
GB_EXISTS="false"
GB_SIZE=0
if [ -f "$GB_FILE" ]; then
    GB_EXISTS="true"
    GB_SIZE=$(stat -c %s "$GB_FILE" 2>/dev/null || echo "0")
fi

# Check Report file
REPORT_FILE="${RESULTS_DIR}/trypsin_fragments_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
fi

# Create JSON result (use temp file for permission safety)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "gb_exists": $GB_EXISTS,
    "gb_size": $GB_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/proteomics_task_result.json 2>/dev/null || sudo rm -f /tmp/proteomics_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/proteomics_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/proteomics_task_result.json
chmod 666 /tmp/proteomics_task_result.json 2>/dev/null || sudo chmod 666 /tmp/proteomics_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/proteomics_task_result.json"
cat /tmp/proteomics_task_result.json
echo "=== Export complete ==="