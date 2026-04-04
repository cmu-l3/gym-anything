#!/bin/bash
echo "=== Exporting analyze_aerodynamic_braking_effectiveness result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_FILE="/home/ga/Documents/projects/braking_analysis.wpa"
REPORT_FILE="/home/ga/Documents/projects/runaway_report.txt"

# 1. Check Project File
PROJECT_EXISTS="false"
PROJECT_SIZE=0
PROJECT_CREATED_DURING_TASK="false"

if [ -f "$PROJECT_FILE" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_FILE" 2>/dev/null || echo "0")
    PROJECT_MTIME=$(stat -c%Y "$PROJECT_FILE" 2>/dev/null || echo "0")
    
    if [ "$PROJECT_MTIME" -gt "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Report File & Extract Values
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
TSR_0_VAL=""
TSR_5_VAL=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c%Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi

    # Extract values using robust grep/regex
    # Looking for patterns like "Runaway_TSR_0deg: 13.5" or "0deg: 13.5"
    
    # Extract 0 degree value (find line with 0, then extract number)
    TSR_0_LINE=$(grep -i "0.*deg" "$REPORT_FILE" | head -n 1)
    if [ -n "$TSR_0_LINE" ]; then
        TSR_0_VAL=$(echo "$TSR_0_LINE" | grep -oE "[0-9]+(\.[0-9]+)?")
    fi

    # Extract 5 degree value
    TSR_5_LINE=$(grep -i "5.*deg" "$REPORT_FILE" | head -n 1)
    if [ -n "$TSR_5_LINE" ]; then
        TSR_5_VAL=$(echo "$TSR_5_LINE" | grep -oE "[0-9]+(\.[0-9]+)?")
    fi
fi

# 3. Check App State
APP_RUNNING=$(pgrep -f "QBlade" > /dev/null && echo "true" || echo "false")

# 4. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_size": $PROJECT_SIZE,
    "project_created_during_task": $PROJECT_CREATED_DURING_TASK,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "tsr_0_val": "${TSR_0_VAL:-0}",
    "tsr_5_val": "${TSR_5_VAL:-0}",
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
write_result_json "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="