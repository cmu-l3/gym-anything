#!/bin/bash
set -euo pipefail

echo "=== Exporting geo_triaxiality_drift_analysis results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/geo_drift_sim.script"
REPORT_PATH="/home/ga/GMAT_output/geo_drift_report.txt"

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

# Extract values from the report file
INIT_LON="0"
FINAL_LON="0"
DRIFT_MAG="0"
GRAVITY_MODEL="unknown"
DEG_ORDER="0"

if [ -f "$REPORT_PATH" ]; then
    INIT_LON=$(grep -ioP 'initial_longitude_deg:\s*\K-?[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    FINAL_LON=$(grep -ioP 'final_longitude_deg:\s*\K-?[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    DRIFT_MAG=$(grep -ioP 'drift_magnitude_deg:\s*\K-?[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    GRAVITY_MODEL=$(grep -ioP 'gravity_model_used:\s*\K[A-Za-z0-9_-]+' "$REPORT_PATH" 2>/dev/null | head -1 || echo "unknown")
    DEG_ORDER=$(grep -ioP 'degree_and_order:\s*\K[0-9]+' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
fi

# Re-run the script through GmatConsole to check if it's a valid GMAT script
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Testing script via GmatConsole..."
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
    "console_run_success": "$RUN_SUCCESS",
    "reported_initial_lon": "$INIT_LON",
    "reported_final_lon": "$FINAL_LON",
    "reported_drift_mag": "$DRIFT_MAG",
    "reported_gravity_model": "$GRAVITY_MODEL",
    "reported_deg_order": "$DEG_ORDER",
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