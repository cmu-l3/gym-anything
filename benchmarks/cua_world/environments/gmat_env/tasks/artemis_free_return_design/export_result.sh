#!/bin/bash
set -euo pipefail

echo "=== Exporting artemis_free_return_design results ==="
source /workspace/scripts/task_utils.sh || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/artemis_free_return.script"
RESULTS_PATH="/home/ga/GMAT_output/free_return_results.txt"

take_screenshot /tmp/task_final.png

check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath")
        local size=$(stat -c %s "$fpath")
        local created=$([ "$mtime" -ge "$TASK_START" ] && echo "true" || echo "false")
        echo "{\"exists\": true, \"size\": $size, \"created_during_task\": $created}"
    else
        echo "{\"exists\": false, \"size\": 0, \"created_during_task\": false}"
    fi
}

SCRIPT_STATS=$(check_file "$SCRIPT_PATH")
RESULTS_STATS=$(check_file "$RESULTS_PATH")

CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
DC_CONVERGED="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    if timeout 120 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_run.txt 2>&1; then
        RUN_SUCCESS="true"
    else
        RUN_SUCCESS="false"
    fi
    
    if grep -qi "converged" /tmp/gmat_console_run.txt 2>/dev/null; then
        DC_CONVERGED="true"
    fi
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "results_file": $RESULTS_STATS,
    "console_run_success": "$RUN_SUCCESS",
    "dc_converged": $DC_CONVERGED,
    "script_path": "$SCRIPT_PATH",
    "results_path": "$RESULTS_PATH"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="