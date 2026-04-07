#!/bin/bash
set -euo pipefail

echo "=== Exporting geo_stationkeeping_budget results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/missions/stationkeeping.script"
REPORT_PATH="/home/ga/GMAT_output/stationkeeping_budget.txt"

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

# Re-run the agent's script via GmatConsole for anti-gaming (ensuring it actually runs)
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 180 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_run.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

# Check if application was running
APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Verify if orbit data was actually generated (any .txt file in GMAT_output modified during task, excluding the budget report itself)
ORBIT_DATA_GENERATED="false"
if [ -d "/home/ga/GMAT_output" ]; then
    for f in /home/ga/GMAT_output/*.txt; do
        if [ "$f" != "$REPORT_PATH" ] && [ -f "$f" ]; then
            mtime=$(stat -c %Y "$f")
            if [ "$mtime" -ge "$TASK_START" ]; then
                ORBIT_DATA_GENERATED="true"
                break
            fi
        fi
    done
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "orbit_data_generated": $ORBIT_DATA_GENERATED,
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