#!/bin/bash
set -euo pipefail

echo "=== Exporting sso_precise_inclination_targeting results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/missions/sso_baseline.script"
REPORT_PATH="/home/ga/GMAT_output/precise_sso_report.txt"

# Take final screenshot
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

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Run script silently to verify it executes and converges
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
ORBIT_REPORT_PATH="/home/ga/GMAT_output/OrbitData.txt"

if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole to confirm targeting convergence..."
    rm -f "$ORBIT_REPORT_PATH"
    timeout 180 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_sso.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

# Extract values from agent's report
REPORTED_INC="0"
REPORTED_RAAN="0"
if [ -f "$REPORT_PATH" ]; then
    REPORTED_INC=$(grep -ioP 'converged_inclination_deg:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    REPORTED_RAAN=$(grep -ioP 'final_raan_deg:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
fi

# Extract final RAAN from generated OrbitData.txt (if it ran)
ACTUAL_FINAL_RAAN="0"
if [ -f "$ORBIT_REPORT_PATH" ]; then
    # Parse the last line, last column (which is RAAN)
    ACTUAL_FINAL_RAAN=$(tail -n 1 "$ORBIT_REPORT_PATH" | awk '{print $NF}' 2>/dev/null || echo "0")
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
    "reported_inc": "$REPORTED_INC",
    "reported_raan": "$REPORTED_RAAN",
    "actual_final_raan": "$ACTUAL_FINAL_RAAN",
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