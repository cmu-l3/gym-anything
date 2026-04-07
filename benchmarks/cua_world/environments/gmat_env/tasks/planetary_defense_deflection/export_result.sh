#!/bin/bash
set -euo pipefail

echo "=== Exporting planetary_defense_deflection results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/asteroid_deflection.script"
REPORT_PATH="/home/ga/GMAT_output/deflection_report.txt"

# Clear any previous DC1 report file from setup/warmup
rm -f /tmp/DC1_report.txt

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

# Programmatically evaluate the agent's completed script by running it!
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
TARGETER_CONVERGED="false"
ACTUAL_DV_KMS="0"

if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running agent script via GmatConsole..."
    if timeout 180 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_pdc.txt 2>&1; then
        RUN_SUCCESS="true"
    else
        RUN_SUCCESS="false"
    fi
    
    # Check if the Differential Corrector generated a report and converged
    if [ -f /tmp/DC1_report.txt ]; then
        if grep -qi "Targeter Converged" /tmp/DC1_report.txt; then
            TARGETER_CONVERGED="true"
            # Get the converged Element1 value from the "Final Variable values:" block
            ACTUAL_DV_KMS=$(grep -oP 'DeflectionBurn\.Element1\s*=\s*\K[+-]?[0-9]*\.?[0-9]+([eE][+-]?[0-9]+)?' /tmp/DC1_report.txt | tail -1 || echo "0")
        fi
    fi
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Parse the agent's report for their reported values
REPORTED_RMAG="0"
REPORTED_DV="0"
if [ -f "$REPORT_PATH" ]; then
    REPORTED_RMAG=$(grep -i "target_rmag_km:" "$REPORT_PATH" | awk -F: '{print $2}' | tr -d ' ' | grep -oE '[+-]?[0-9]*\.?[0-9]+' || echo "0")
    REPORTED_DV=$(grep -i "required_dv_cm_s:" "$REPORT_PATH" | awk -F: '{print $2}' | tr -d ' ' | grep -oE '[+-]?[0-9]*\.?[0-9]+' || echo "0")
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
    "targeter_converged": "$TARGETER_CONVERGED",
    "actual_dv_kms": "$ACTUAL_DV_KMS",
    "reported_rmag_km": "$REPORTED_RMAG",
    "reported_dv_cm_s": "$REPORTED_DV",
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