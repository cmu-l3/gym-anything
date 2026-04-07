#!/bin/bash
set -euo pipefail

echo "=== Exporting suborbital_splashdown_dispersion results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/splashdown_sim.script"
REPORT_PATH="/home/ga/GMAT_output/dispersion_results.txt"

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

CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 180 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_splash.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

LAT_1="0"; LON_1="0"; TOF_1="0"
HAS_CASE2="false"; HAS_CASE3="false"

if [ -f "$REPORT_PATH" ]; then
    LAT_1=$(grep -A 3 -i "CASE 1" "$REPORT_PATH" | grep -i "Latitude" | grep -oP '\-?[0-9]+\.?[0-9]*' | head -1 || echo "0")
    LON_1=$(grep -A 3 -i "CASE 1" "$REPORT_PATH" | grep -i "Longitude" | grep -oP '\-?[0-9]+\.?[0-9]*' | head -1 || echo "0")
    TOF_1=$(grep -A 3 -i "CASE 1" "$REPORT_PATH" | grep -i "Flight" | grep -oP '\-?[0-9]+\.?[0-9]*' | head -1 || echo "0")
    
    grep -qi "CASE 2" "$REPORT_PATH" && HAS_CASE2="true" || HAS_CASE2="false"
    grep -qi "CASE 3" "$REPORT_PATH" && HAS_CASE3="true" || HAS_CASE3="false"
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
    "case1_lat": "$LAT_1",
    "case1_lon": "$LON_1",
    "case1_tof": "$TOF_1",
    "has_case2": $HAS_CASE2,
    "has_case3": $HAS_CASE3,
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