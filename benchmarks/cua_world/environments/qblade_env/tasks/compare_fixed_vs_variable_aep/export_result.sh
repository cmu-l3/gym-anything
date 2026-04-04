#!/bin/bash
echo "=== Exporting compare_fixed_vs_variable_aep results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check output files
FIXED_PATH="/home/ga/Documents/fixed_power_curve.txt"
VAR_PATH="/home/ga/Documents/variable_power_curve.txt"

check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true|$size"
        else
            echo "false|$size" # Exists but old
        fi
    else
        echo "false|0"
    fi
}

FIXED_INFO=$(check_file "$FIXED_PATH")
FIXED_CREATED=$(echo "$FIXED_INFO" | cut -d'|' -f1)
FIXED_SIZE=$(echo "$FIXED_INFO" | cut -d'|' -f2)

VAR_INFO=$(check_file "$VAR_PATH")
VAR_CREATED=$(echo "$VAR_INFO" | cut -d'|' -f1)
VAR_SIZE=$(echo "$VAR_INFO" | cut -d'|' -f2)

# Check if QBlade is running
APP_RUNNING=$(is_qblade_running)
APP_RUNNING_BOOL="false"
if [ "$APP_RUNNING" -gt "0" ]; then
    APP_RUNNING_BOOL="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "fixed_file_exists": $([ -f "$FIXED_PATH" ] && echo "true" || echo "false"),
    "fixed_file_created_during_task": $FIXED_CREATED,
    "fixed_file_size": $FIXED_SIZE,
    "fixed_file_path": "$FIXED_PATH",
    "variable_file_exists": $([ -f "$VAR_PATH" ] && echo "true" || echo "false"),
    "variable_file_created_during_task": $VAR_CREATED,
    "variable_file_size": $VAR_SIZE,
    "variable_file_path": "$VAR_PATH",
    "app_was_running": $APP_RUNNING_BOOL,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
write_result_json "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="