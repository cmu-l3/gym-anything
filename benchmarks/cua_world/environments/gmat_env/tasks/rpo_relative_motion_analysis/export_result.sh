#!/bin/bash
set -euo pipefail

echo "=== Exporting rpo_relative_motion_analysis results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/rpo_drift.script"
SUMMARY_PATH="/home/ga/GMAT_output/rpo_summary.txt"

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
SUMMARY_STATS=$(check_file "$SUMMARY_PATH")

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Parse the summary text file for values
MIN_RANGE="-1"
MAX_RANGE="-1"
PASSIVE_VIOLATED="unknown"

if [ -f "$SUMMARY_PATH" ]; then
    MIN_RANGE=$(grep -ioP 'min_range_km:\s*\K[0-9]+\.?[0-9]*' "$SUMMARY_PATH" | head -1 || echo "-1")
    MAX_RANGE=$(grep -ioP 'max_range_km:\s*\K[0-9]+\.?[0-9]*' "$SUMMARY_PATH" | head -1 || echo "-1")
    PASSIVE_VIOLATED=$(grep -ioP 'passive_safety_violated:\s*\K(true|false)' "$SUMMARY_PATH" | head -1 | tr 'A-Z' 'a-z' || echo "unknown")
fi

# Re-run the script via GmatConsole to check script validity
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 180 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_output.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "summary_file": $SUMMARY_STATS,
    "min_range_km": "$MIN_RANGE",
    "max_range_km": "$MAX_RANGE",
    "passive_safety_violated": "$PASSIVE_VIOLATED",
    "console_run_success": "$RUN_SUCCESS",
    "script_path": "$SCRIPT_PATH",
    "summary_path": "$SUMMARY_PATH",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="