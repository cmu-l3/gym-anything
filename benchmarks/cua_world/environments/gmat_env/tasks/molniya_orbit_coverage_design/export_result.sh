#!/bin/bash
set -euo pipefail

echo "=== Exporting molniya_orbit_coverage_design results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/molniya_mission.script"
REPORT_PATH="/home/ga/GMAT_output/molniya_analysis.txt"

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

# Re-run script via GmatConsole to verify it's valid
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 180 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_output.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Parse values from report (if exists)
SMA_VAL="-1"; ECC_VAL="-1"; INC_VAL="-1"
AOP_INIT="-1"; AOP_FIN="-1"; AOP_DRIFT="-1"
APOGEE="-1"; PERIGEE="-1"; PERIOD="-1"

if [ -f "$REPORT_PATH" ]; then
    SMA_VAL=$(grep -ioP 'SMA_km:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "-1")
    ECC_VAL=$(grep -ioP 'ECC:\s*\K[0-9]+\.?[0-9e+-]*' "$REPORT_PATH" | head -1 || echo "-1")
    INC_VAL=$(grep -ioP 'INC_deg:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "-1")
    AOP_INIT=$(grep -ioP 'AOP_initial_deg:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "-1")
    AOP_FIN=$(grep -ioP 'AOP_final_deg:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "-1")
    AOP_DRIFT=$(grep -ioP 'AOP_drift_deg:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "-1")
    APOGEE=$(grep -ioP 'apogee_alt_km:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "-1")
    PERIGEE=$(grep -ioP 'perigee_alt_km:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "-1")
    PERIOD=$(grep -ioP 'period_hours:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" | head -1 || echo "-1")
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
    "report_sma_km": "$SMA_VAL",
    "report_ecc": "$ECC_VAL",
    "report_inc_deg": "$INC_VAL",
    "report_aop_initial_deg": "$AOP_INIT",
    "report_aop_final_deg": "$AOP_FIN",
    "report_aop_drift_deg": "$AOP_DRIFT",
    "report_apogee_km": "$APOGEE",
    "report_perigee_km": "$PERIGEE",
    "report_period_hours": "$PERIOD",
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