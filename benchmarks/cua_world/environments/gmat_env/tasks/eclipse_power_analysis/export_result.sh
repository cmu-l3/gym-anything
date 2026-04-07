#!/bin/bash
set -euo pipefail

echo "=== Exporting eclipse_power_analysis results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/skywatch3_eclipse.script"
REPORT_PATH="/home/ga/GMAT_output/eclipse_analysis_report.txt"

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

# Run script via console to check for errors/generate output if the agent didn't
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 180 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_run.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

# Re-check report
REPORT_STATS_RERUN=$(check_file "$REPORT_PATH")

# Extract params from script
SMA_VAL="0"; INC_VAL="0"; RAAN_VAL="0"
ECLIPSE_LOCATOR="false"
PROPAGATION_30DAYS="false"

if [ -f "$SCRIPT_PATH" ]; then
    SMA_VAL=$(grep -oP 'SMA\s*=\s*\K[0-9]+\.?[0-9]*' "$SCRIPT_PATH" 2>/dev/null | head -1 || echo "0")
    INC_VAL=$(grep -oP 'INC\s*=\s*\K[0-9]+\.?[0-9]*' "$SCRIPT_PATH" 2>/dev/null | head -1 || echo "0")
    RAAN_VAL=$(grep -oP 'RAAN\s*=\s*\K[0-9]+\.?[0-9]*' "$SCRIPT_PATH" 2>/dev/null | head -1 || echo "0")
    
    if grep -qi "EclipseLocator" "$SCRIPT_PATH"; then
        ECLIPSE_LOCATOR="true"
    fi
    
    # 30 days is ~2592000 seconds
    if grep -q "ElapsedDays\s*=\s*30\|ElapsedSecs\s*=\s*2592000" "$SCRIPT_PATH" 2>/dev/null; then
        PROPAGATION_30DAYS="true"
    elif grep -oP 'ElapsedDays\s*=\s*\K[0-9]+' "$SCRIPT_PATH" 2>/dev/null | awk '{if ($1>=25 && $1<=35) exit 0; else exit 1}'; then
        PROPAGATION_30DAYS="true"
    fi
fi

# Check if EclipseLocator data file was generated
ECLIPSE_DATA_EXISTS="false"
if [ "$(find /home/ga/GMAT_output -maxdepth 1 -name "*.txt" -not -name "eclipse_analysis_report.txt" -not -name "gmat_console_run.txt" 2>/dev/null | wc -l)" -gt 0 ]; then
    ECLIPSE_DATA_EXISTS="true"
fi

# Extract values from report
NUM_ECLIPSES="0"
MAX_ECLIPSE="0"
AVG_ECLIPSE="0"
ECLIPSE_FRAC="0"
REQ_WH="0"
MARGIN="0"
BATTERY_ADEQUATE="UNKNOWN"

if [ -f "$REPORT_PATH" ]; then
    NUM_ECLIPSES=$(grep -oP 'num_eclipses:\s*\K[0-9]+' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    MAX_ECLIPSE=$(grep -oP 'max_eclipse_min:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    AVG_ECLIPSE=$(grep -oP 'avg_eclipse_min:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    ECLIPSE_FRAC=$(grep -oP 'eclipse_fraction:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    REQ_WH=$(grep -oP 'required_Wh:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    MARGIN=$(grep -oP 'margin_percent:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    
    if grep -qi "battery_adequate:\s*YES" "$REPORT_PATH"; then
        BATTERY_ADEQUATE="YES"
    elif grep -qi "battery_adequate:\s*NO" "$REPORT_PATH"; then
        BATTERY_ADEQUATE="NO"
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
    "report_file_rerun": $REPORT_STATS_RERUN,
    "console_run_success": "$RUN_SUCCESS",
    "script_sma": "$SMA_VAL",
    "script_inc": "$INC_VAL",
    "script_raan": "$RAAN_VAL",
    "eclipse_locator": $ECLIPSE_LOCATOR,
    "propagation_30days": $PROPAGATION_30DAYS,
    "eclipse_data_exists": $ECLIPSE_DATA_EXISTS,
    "num_eclipses": "$NUM_ECLIPSES",
    "max_eclipse_min": "$MAX_ECLIPSE",
    "avg_eclipse_min": "$AVG_ECLIPSE",
    "eclipse_fraction": "$ECLIPSE_FRAC",
    "required_Wh": "$REQ_WH",
    "margin_percent": "$MARGIN",
    "battery_adequate": "$BATTERY_ADEQUATE",
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