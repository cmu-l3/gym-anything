#!/bin/bash
echo "=== Exporting insulin_restriction_cloning results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/results"
GB_FILE="${RESULTS_DIR}/insulin_restriction_annotated.gb"
REPORT_FILE="${RESULTS_DIR}/cloning_strategy_report.txt"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check GenBank file
GB_EXISTS="false"
GB_SIZE=0
GB_MTIME=0
if [ -f "$GB_FILE" ]; then
    GB_EXISTS="true"
    GB_SIZE=$(stat -c %s "$GB_FILE" 2>/dev/null || echo "0")
    GB_MTIME=$(stat -c %Y "$GB_FILE" 2>/dev/null || echo "0")
fi

# Check Report file
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
fi

# Write summary JSON for the verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "gb_exists": $GB_EXISTS,
    "gb_size": $GB_SIZE,
    "gb_mtime": $GB_MTIME,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME
}
EOF

# Move to final location safely
rm -f /tmp/insulin_cloning_result.json 2>/dev/null || sudo rm -f /tmp/insulin_cloning_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/insulin_cloning_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/insulin_cloning_result.json
chmod 666 /tmp/insulin_cloning_result.json 2>/dev/null || sudo chmod 666 /tmp/insulin_cloning_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/insulin_cloning_result.json"
cat /tmp/insulin_cloning_result.json
echo "=== Export complete ==="