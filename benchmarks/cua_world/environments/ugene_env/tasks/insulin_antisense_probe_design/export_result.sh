#!/bin/bash
echo "=== Exporting insulin_antisense_probe_design results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/UGENE_Data/results/antisense_probe"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize tracking variables
SENSE_EXISTS="false"
ANTISENSE_EXISTS="false"
REPORT_EXISTS="false"

SENSE_SEQ=""
ANTISENSE_SEQ=""
REPORT_TEXT=""

# 1. Check Sense FASTA
SENSE_FILE="${RESULTS_DIR}/insulin_cds_sense.fasta"
if [ -f "$SENSE_FILE" ] && [ -s "$SENSE_FILE" ]; then
    SENSE_EXISTS="true"
    # Extract just the sequence (ignore > headers), remove whitespace, convert to uppercase
    SENSE_SEQ=$(grep -v "^>" "$SENSE_FILE" 2>/dev/null | tr -d '\n\r ' | tr 'a-z' 'A-Z')
fi

# 2. Check Antisense FASTA
ANTISENSE_FILE="${RESULTS_DIR}/insulin_cds_antisense.fasta"
if [ -f "$ANTISENSE_FILE" ] && [ -s "$ANTISENSE_FILE" ]; then
    ANTISENSE_EXISTS="true"
    # Extract just the sequence (ignore > headers), remove whitespace, convert to uppercase
    ANTISENSE_SEQ=$(grep -v "^>" "$ANTISENSE_FILE" 2>/dev/null | tr -d '\n\r ' | tr 'a-z' 'A-Z')
fi

# 3. Check Report
REPORT_FILE="${RESULTS_DIR}/probe_design_report.txt"
if [ -f "$REPORT_FILE" ] && [ -s "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Get the first 2000 characters of the report to avoid massive JSON if they exported wrong thing
    REPORT_TEXT=$(head -c 2000 "$REPORT_FILE" 2>/dev/null)
fi

# Escape report text to make it JSON safe
REPORT_ESCAPED=$(echo "$REPORT_TEXT" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))')

# Check if application is running
APP_RUNNING=$(pgrep -f "ugene" > /dev/null && echo "true" || echo "false")

# Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_ts": $TASK_START,
    "app_was_running": $APP_RUNNING,
    "sense_exists": $SENSE_EXISTS,
    "antisense_exists": $ANTISENSE_EXISTS,
    "report_exists": $REPORT_EXISTS,
    "sense_seq": "$SENSE_SEQ",
    "antisense_seq": "$ANTISENSE_SEQ",
    "report_text": $REPORT_ESCAPED
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results successfully exported to /tmp/task_result.json"
echo "=== Export complete ==="