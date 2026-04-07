#!/bin/bash
set -euo pipefail

echo "=== Exporting lunar_orbit_insertion_design results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Find the most recently modified script in the user's home directory
SCRIPT_PATH=$(find /home/ga -name "*.script" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2- || echo "")
RESULTS_PATH="/home/ga/GMAT_output/lunar_transfer_results.txt"

check_file() {
    local fpath="$1"
    if [ -n "$fpath" ] && [ -f "$fpath" ]; then
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

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Parse results file
TLI_DV="0"
LOI_DV="0"
TOTAL_DV="0"
TRANSFER_TIME="0"
FINAL_ALT="0"

if [ -f "$RESULTS_PATH" ]; then
    TLI_DV=$(grep -ioP 'TLI_DeltaV_mps:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    LOI_DV=$(grep -ioP 'LOI_DeltaV_mps:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    TOTAL_DV=$(grep -ioP 'Total_DeltaV_mps:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    TRANSFER_TIME=$(grep -ioP 'TransferTime_days:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    FINAL_ALT=$(grep -ioP 'FinalLunarAlt_km:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
fi

# Re-run the script via GmatConsole (timeout of 300s since optimization can be slow)
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -n "$SCRIPT_PATH" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 300 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_lunar.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "results_file": $RESULTS_STATS,
    "script_path": "$SCRIPT_PATH",
    "results_path": "$RESULTS_PATH",
    "tli_dv_mps": "$TLI_DV",
    "loi_dv_mps": "$LOI_DV",
    "total_dv_mps": "$TOTAL_DV",
    "transfer_time_days": "$TRANSFER_TIME",
    "final_lunar_alt_km": "$FINAL_ALT",
    "console_run_success": "$RUN_SUCCESS"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="