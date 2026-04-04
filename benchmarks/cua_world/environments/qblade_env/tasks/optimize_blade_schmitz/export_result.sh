#!/bin/bash
echo "=== Exporting optimize_blade_schmitz results ==="

source /workspace/scripts/task_utils.sh

# 1. Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 3. Verify Project File (.wpa)
PROJECT_FILE="/home/ga/Documents/projects/optimized_rotor.wpa"
PROJECT_EXISTS="false"
PROJECT_SIZE=0
PROJECT_CREATED_DURING_TASK="false"

if [ -f "$PROJECT_FILE" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_FILE")
    FILE_MTIME=$(stat -c%Y "$PROJECT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    fi
fi

# 4. Verify Results Text File
RESULTS_FILE="/home/ga/Documents/projects/results.txt"
RESULTS_EXISTS="false"
RESULTS_CONTENT=""
PARSED_CP=0
PARSED_TSR=0

if [ -f "$RESULTS_FILE" ]; then
    RESULTS_EXISTS="true"
    RESULTS_CONTENT=$(cat "$RESULTS_FILE" | head -n 5) # Limit content length
    
    # Simple grep/regex to try and parse numbers for JSON (best effort)
    # Looks for numbers like 0.45 or 7.0
    PARSED_CP=$(grep -oE "0\.[0-9]+" "$RESULTS_FILE" | head -1 || echo "0")
    PARSED_TSR=$(grep -oE "[0-9]+\.?[0-9]*" "$RESULTS_FILE" | grep -v "$PARSED_CP" | head -1 || echo "0")
fi

# 5. Check if QBlade is still running
APP_RUNNING=$(is_qblade_running)

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_size_bytes": $PROJECT_SIZE,
    "project_created_during_task": $PROJECT_CREATED_DURING_TASK,
    "results_file_exists": $RESULTS_EXISTS,
    "results_content_sample": "$(echo "$RESULTS_CONTENT" | sed 's/"/\\"/g')",
    "parsed_cp_max": "$PARSED_CP",
    "parsed_tsr_opt": "$PARSED_TSR",
    "app_was_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Safe Export
write_result_json "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="