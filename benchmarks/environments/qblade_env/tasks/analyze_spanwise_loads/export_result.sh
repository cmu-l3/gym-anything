#!/bin/bash
echo "=== Exporting analyze_spanwise_loads result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Data Export File
DATA_FILE="/home/ga/Documents/spanwise_loads.txt"
DATA_EXISTS="false"
DATA_SIZE=0
DATA_CREATED_DURING_TASK="false"
DATA_LINES=0

if [ -f "$DATA_FILE" ]; then
    DATA_EXISTS="true"
    DATA_SIZE=$(stat -c %s "$DATA_FILE" 2>/dev/null || echo "0")
    DATA_MTIME=$(stat -c %Y "$DATA_FILE" 2>/dev/null || echo "0")
    
    if [ "$DATA_MTIME" -ge "$TASK_START" ]; then
        DATA_CREATED_DURING_TASK="true"
    fi
    
    # Count lines that look like data (numbers)
    DATA_LINES=$(grep -cE '^[[:space:]]*-?[0-9]+\.?[0-9]*' "$DATA_FILE" 2>/dev/null || echo "0")
fi

# 2. Check Report File
REPORT_FILE="/home/ga/Documents/max_load_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_CREATED_DURING_TASK="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
    
    # Read content (safe read)
    REPORT_CONTENT=$(head -n 5 "$REPORT_FILE")
fi

# 3. Check App State
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# 4. Take final screenshot for VLM verification
take_screenshot /tmp/task_final.png

# 5. Construct JSON Result
# We will save the actual data content to a temp file to be read by python verifier
# because passing large multiline strings in JSON via bash is error-prone.
if [ "$DATA_EXISTS" == "true" ]; then
    cp "$DATA_FILE" /tmp/spanwise_data_export.txt
    chmod 666 /tmp/spanwise_data_export.txt
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "data_exists": $DATA_EXISTS,
    "data_created_during_task": $DATA_CREATED_DURING_TASK,
    "data_size_bytes": $DATA_SIZE,
    "data_lines": $DATA_LINES,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content": "$(echo "$REPORT_CONTENT" | sed 's/"/\\"/g' | tr -d '\n')",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "exported_data_path": "/tmp/spanwise_data_export.txt"
}
EOF

# Save result safely
write_result_json "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="