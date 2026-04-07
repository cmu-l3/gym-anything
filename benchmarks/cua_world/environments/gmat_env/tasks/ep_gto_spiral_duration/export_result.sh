#!/bin/bash
set -euo pipefail

echo "=== Exporting ep_gto_spiral_duration results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/ep_spiral.script"
REPORT_PATH="/home/ga/GMAT_output/ep_spiral_report.txt"

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

# Re-run the corrected script through GmatConsole to get actual outputs
# This checks for structural validity and physics behavior even if agent fakes the report
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    # Point mass finite burns take a bit of time; 120 seconds should be plenty
    timeout 120 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_output.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

# Re-check report file (in case the re-run generated it properly)
REPORT_STATS_RERUN=$(check_file "$REPORT_PATH")

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Extract key parameters from the agent's report file
ELAPSED_DAYS="0"
REMAINING_FUEL="0"
FINAL_SMA="0"
FINAL_ECC="0"
FINAL_INC="0"

if [ -f "$REPORT_PATH" ]; then
    ELAPSED_DAYS=$(grep -ioP 'elapsed_days\s*[:=]\s*\K[0-9]+\.?[0-9eE+-]*' "$REPORT_PATH" | head -1 || echo "0")
    REMAINING_FUEL=$(grep -ioP 'remaining_fuel_kg\s*[:=]\s*\K[0-9]+\.?[0-9eE+-]*' "$REPORT_PATH" | head -1 || echo "0")
    FINAL_SMA=$(grep -ioP 'final_sma_km\s*[:=]\s*\K[0-9]+\.?[0-9eE+-]*' "$REPORT_PATH" | head -1 || echo "0")
    FINAL_ECC=$(grep -ioP 'final_eccentricity\s*[:=]\s*\K[0-9]+\.?[0-9eE+-]*' "$REPORT_PATH" | head -1 || echo "0")
    FINAL_INC=$(grep -ioP 'final_inclination_deg\s*[:=]\s*\K[0-9]+\.?[0-9eE+-]*' "$REPORT_PATH" | head -1 || echo "0")
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "report_file_rerun": $REPORT_STATS_RERUN,
    "console_run_success": "$RUN_SUCCESS",
    "elapsed_days": "$ELAPSED_DAYS",
    "remaining_fuel_kg": "$REMAINING_FUEL",
    "final_sma_km": "$FINAL_SMA",
    "final_eccentricity": "$FINAL_ECC",
    "final_inclination_deg": "$FINAL_INC",
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