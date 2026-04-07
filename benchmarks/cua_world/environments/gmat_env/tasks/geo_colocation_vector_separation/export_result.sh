#!/bin/bash
set -euo pipefail

echo "=== Exporting geo_colocation_vector_separation results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/geo_colocation.script"
REPORT_PATH="/home/ga/GMAT_output/colocation_ephem.txt"

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

# Re-run the script via GmatConsole to ensure the report file is generated/updated properly
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 120 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_output.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

REPORT_STATS=$(check_file "$REPORT_PATH")
APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Basic check: do we have at least 2 spacecraft defined?
NUM_SPACECRAFT=0
SIMULTANEOUS_PROP="false"
if [ -f "$SCRIPT_PATH" ]; then
    NUM_SPACECRAFT=$(grep -ic "Create Spacecraft" "$SCRIPT_PATH" || echo "0")
    if grep -iq "Propagate.*EuroSat4.*EuroSat8\|Propagate.*EuroSat8.*EuroSat4" "$SCRIPT_PATH"; then
        SIMULTANEOUS_PROP="true"
    fi
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "console_run_success": "$RUN_SUCCESS",
    "num_spacecraft": $NUM_SPACECRAFT,
    "simultaneous_prop_in_script": $SIMULTANEOUS_PROP,
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