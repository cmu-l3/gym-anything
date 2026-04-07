#!/bin/bash
# Export script for pasat_processing_chunking_analysis
set -e
echo "=== Exporting PASAT Chunking Analysis Result ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
scrot /tmp/task_final.png 2>/dev/null || true

# Check report properties
REPORT_PATH="/home/ga/pebl/analysis/pasat_report.json"
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_SIZE=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# We stage the files in /tmp so the verifier can copy them safely
cp "$REPORT_PATH" /tmp/agent_report.json 2>/dev/null || true
cp "/home/ga/pebl/data/pasat_data.csv" /tmp/pasat_data.csv 2>/dev/null || true

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_size_bytes": $REPORT_SIZE
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="