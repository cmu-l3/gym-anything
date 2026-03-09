#!/bin/bash
set -e
echo "=== Exporting configure_av_coaching_profile results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final system state (Backup verification)
take_screenshot /tmp/system_final_state.png

# 2. Get Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Analyze Agent Evidence Files
check_evidence_file() {
    local filepath="$1"
    local key_prefix="$2"
    
    if [ -f "$filepath" ]; then
        echo "\"${key_prefix}_exists\": true,"
        
        # Check size (non-empty)
        local size=$(stat -c %s "$filepath")
        echo "\"${key_prefix}_size\": $size,"
        
        # Check modification time vs task start (Anti-gaming)
        local mtime=$(stat -c %Y "$filepath")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "\"${key_prefix}_created_during_task\": true,"
        else
            echo "\"${key_prefix}_created_during_task\": false,"
        fi
    else
        echo "\"${key_prefix}_exists\": false,"
        echo "\"${key_prefix}_size\": 0,"
        echo "\"${key_prefix}_created_during_task\": false,"
    fi
}

# 4. Check if screenshots differ from initial state (Anti-gaming "Do Nothing" check)
# Simple size comparison as a proxy for visual change
INITIAL_SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
FINAL_SIZE=$(stat -c %s /tmp/av_config_final.png 2>/dev/null || echo "0")
DIFF_SIZE=$(( FINAL_SIZE - INITIAL_SIZE ))
# Absolute value
if [ $DIFF_SIZE -lt 0 ]; then DIFF_SIZE=$(( -DIFF_SIZE )); fi

STATE_CHANGED="false"
if [ "$DIFF_SIZE" -gt 500 ]; then
    STATE_CHANGED="true"
fi

# 5. Check if Firefox is still running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# 6. Generate JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "state_changed_from_initial": $STATE_CHANGED,
    $(check_evidence_file "/tmp/noise_suppression_evidence.png" "noise_evidence")
    $(check_evidence_file "/tmp/av_config_final.png" "final_view")
    "initial_screenshot_path": "/tmp/task_initial_state.png",
    "system_final_screenshot_path": "/tmp/system_final_state.png"
}
EOF

# 7. Move to standard output location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="