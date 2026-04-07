#!/bin/bash
set -euo pipefail

echo "=== Exporting geo_station_relocation results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find the newest script file created during the task
SCRIPT_PATH=$(find /home/ga/Documents/missions /home/ga/GMAT_output -maxdepth 1 -name "*.script" -type f -newermt "@$TASK_START" 2>/dev/null | head -1 || echo "")
if [ -z "$SCRIPT_PATH" ]; then
    # Fallback if timestamps are weird, just find any script named geo_relocation.script
    if [ -f "/home/ga/Documents/missions/geo_relocation.script" ]; then
        SCRIPT_PATH="/home/ga/Documents/missions/geo_relocation.script"
    fi
fi

RESULTS_PATH="/home/ga/GMAT_output/relocation_results.txt"

check_file() {
    local fpath="$1"
    if [ -n "$fpath" ] && [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        local created_during=$([ "$mtime" -ge "$TASK_START" ] && echo "true" || echo "false")
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created_during, \"path\": \"$fpath\"}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false, \"path\": \"$fpath\"}"
    fi
}

SCRIPT_STATS=$(check_file "$SCRIPT_PATH")
RESULTS_STATS=$(check_file "$RESULTS_PATH")

# Optionally run script via GmatConsole to verify it's a valid script
RUN_SUCCESS="false"
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
if [ -n "$CONSOLE" ] && [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 120 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_reloc.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")
SPEC_EXISTS=$([ -f "/home/ga/Desktop/relocation_directive.txt" ] && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "spec_file_exists": $SPEC_EXISTS,
    "console_run_success": "$RUN_SUCCESS",
    "script_file": $SCRIPT_STATS,
    "results_file": $RESULTS_STATS,
    "script_path_actual": "$SCRIPT_PATH"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="