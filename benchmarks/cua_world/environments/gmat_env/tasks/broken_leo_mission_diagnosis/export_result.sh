#!/bin/bash
set -euo pipefail

echo "=== Exporting broken_leo_mission_diagnosis results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/missions/leo_comms_mission.script"
REPORT_PATH="/home/ga/GMAT_output/leo_diagnosis_report.txt"
ORBIT_REPORT_PATH="/home/ga/GMAT_output/leo_comms_report.txt"

# Capture final screenshot
take_screenshot /tmp/task_final.png

check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        local created_during=$([ "$mtime" -ge "$TASK_START" ] && echo "true" || echo "false")
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

SCRIPT_STATS=$(check_file "$SCRIPT_PATH")
REPORT_STATS=$(check_file "$REPORT_PATH")
ORBIT_REPORT_STATS=$(check_file "$ORBIT_REPORT_PATH")

# Extract key parameters from the (possibly corrected) script
SMA_VAL=$(grep -oP 'SMA\s*=\s*\K[0-9]+\.?[0-9]*' "$SCRIPT_PATH" 2>/dev/null | head -1 || echo "0")
ECC_VAL=$(grep -oP 'ECC\s*=\s*\K[0-9]+\.?[0-9]*' "$SCRIPT_PATH" 2>/dev/null | head -1 || echo "0")
INC_VAL=$(grep -oP 'INC\s*=\s*\K[0-9]+\.?[0-9]*' "$SCRIPT_PATH" 2>/dev/null | head -1 || echo "0")
DRAG_VAL=$(grep -oP 'DragArea\s*=\s*\K[0-9]+\.?[0-9e+-]*' "$SCRIPT_PATH" 2>/dev/null | head -1 || echo "0")

# Re-run the corrected script through GmatConsole to get actual outputs
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 120 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_output.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "orbit_report_file": $ORBIT_REPORT_STATS,
    "script_sma": "$SMA_VAL",
    "script_ecc": "$ECC_VAL",
    "script_inc": "$INC_VAL",
    "script_drag_area": "$DRAG_VAL",
    "console_run_success": "$RUN_SUCCESS",
    "script_path": "$SCRIPT_PATH",
    "report_path": "$REPORT_PATH"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="
