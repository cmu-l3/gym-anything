#!/bin/bash
set -euo pipefail

echo "=== Exporting mars_transfer_trajectory_design results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/mars_transfer.script"
RESULTS_PATH="/home/ga/GMAT_output/mars_transfer_results.txt"

# Take final evidence screenshot
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
RESULTS_STATS=$(check_file "$RESULTS_PATH")

CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 180 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_mars.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

RESULTS_STATS_RERUN=$(check_file "$RESULTS_PATH")

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

C3_VAL="0"
TMI_VAL="0"
TOF_VAL="0"
MARS_CA_VAL="0"

# Robustly extract key metrics from the results file using PCRE
if [ -f "$RESULTS_PATH" ]; then
    C3_VAL=$(grep -ioP 'C3(?:_km2s2)?(?:[:=])?\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" | head -1 || echo "0")
    TMI_VAL=$(grep -ioP 'TMI_DeltaV(?:_kms)?(?:[:=])?\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" | head -1 || echo "0")
    TOF_VAL=$(grep -ioP 'TOF(?:_days)?(?:[:=])?\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" | head -1 || echo "0")
    MARS_CA_VAL=$(grep -ioP 'Mars_CA(?:_km)?(?:[:=])?\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" | head -1 || echo "0")
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "results_file": $RESULTS_STATS,
    "results_file_rerun": $RESULTS_STATS_RERUN,
    "console_run_success": "$RUN_SUCCESS",
    "c3_km2s2": "$C3_VAL",
    "tmi_deltav_kms": "$TMI_VAL",
    "tof_days": "$TOF_VAL",
    "mars_ca_km": "$MARS_CA_VAL",
    "script_path": "$SCRIPT_PATH",
    "results_path": "$RESULTS_PATH"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="