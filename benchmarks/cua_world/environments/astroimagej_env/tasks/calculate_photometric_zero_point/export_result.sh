#!/bin/bash
echo "=== Exporting Calculate Photometric Zero Point Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga

TASK_DIR="/home/ga/AstroImages/zero_point"
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 1. Check for Measurement Files
MEASUREMENT_FILE_EXISTS="false"
MEASUREMENT_FILE_CREATED_DURING_TASK="false"
MEASUREMENT_FILE_PATH=""
MEASUREMENT_FILE_SIZE="0"

POSSIBLE_FILES=$(find "$TASK_DIR" -maxdepth 1 -type f \( -name "*.xls" -o -name "*.csv" -o -name "*.txt" \) | grep -i "measure\|result")
for f in $POSSIBLE_FILES; do
    MEASUREMENT_FILE_EXISTS="true"
    MEASUREMENT_FILE_PATH="$f"
    MEASUREMENT_FILE_SIZE=$(stat -c %s "$f" 2>/dev/null || echo "0")
    
    FILE_MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        MEASUREMENT_FILE_CREATED_DURING_TASK="true"
    fi
    break
done

# 2. Check for Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

REPORT_PATH="$TASK_DIR/zp_report.txt"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    # Grab up to 500 chars of report content to parse the ZP
    REPORT_CONTENT=$(head -c 500 "$REPORT_PATH" | tr -d '\000-\011\013-\037' | sed 's/"/\\"/g')
fi

# 3. Export JSON result
TEMP_JSON=$(mktemp /tmp/zp_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $CURRENT_TIME,
    "measurement_file_exists": $MEASUREMENT_FILE_EXISTS,
    "measurement_file_created_during_task": $MEASUREMENT_FILE_CREATED_DURING_TASK,
    "measurement_file_path": "$MEASUREMENT_FILE_PATH",
    "measurement_file_size": $MEASUREMENT_FILE_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content": "$REPORT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="