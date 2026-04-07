#!/bin/bash
set -euo pipefail

echo "=== Exporting Venus TCM results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

REPORT_PATH="/home/ga/GMAT_output/tcm_report.txt"
# Agent might save over the baseline or create a new file
SCRIPT_PATH_1="/home/ga/Documents/missions/venus_tcm_baseline.script"
SCRIPT_PATH_2="/home/ga/Documents/missions/venus_tcm_targeted.script"

take_screenshot /tmp/task_final.png

# Determine which script was modified/used
FINAL_SCRIPT_PATH=""
if [ -f "$SCRIPT_PATH_2" ]; then
    FINAL_SCRIPT_PATH="$SCRIPT_PATH_2"
elif [ -f "$SCRIPT_PATH_1" ]; then
    FINAL_SCRIPT_PATH="$SCRIPT_PATH_1"
fi

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

SCRIPT_STATS=$(check_file "$FINAL_SCRIPT_PATH")
REPORT_STATS=$(check_file "$REPORT_PATH")

# Re-run script via GmatConsole to confirm mathematical convergence
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
CONSOLE_LOG="/tmp/gmat_console_tcm.txt"

if [ -n "$CONSOLE" ] && [ -n "$FINAL_SCRIPT_PATH" ]; then
    echo "Re-running targeted script via GmatConsole..."
    if timeout 120 "$CONSOLE" --run "$FINAL_SCRIPT_PATH" > "$CONSOLE_LOG" 2>&1; then
        RUN_SUCCESS="true"
    else
        RUN_SUCCESS="false"
    fi
fi

# Extract reported values from agent's text file
RADPER_VAL="0"; INC_VAL="0"; TCM_V="0"; TCM_N="0"
if [ -f "$REPORT_PATH" ]; then
    RADPER_VAL=$(grep -oP 'Achieved_RadPer_km:\s*\K-?[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    INC_VAL=$(grep -oP 'Achieved_INC_deg:\s*\K-?[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    TCM_V=$(grep -oP 'TCM_V_mps:\s*\K-?[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    TCM_N=$(grep -oP 'TCM_N_mps:\s*\K-?[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
fi

# Check for convergence in the console log
TARGETER_CONVERGED="false"
if [ -f "$CONSOLE_LOG" ]; then
    if grep -qi "Targeter.*converged" "$CONSOLE_LOG"; then
        TARGETER_CONVERGED="true"
    fi
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
    "targeter_converged_in_log": $TARGETER_CONVERGED,
    "reported_radper_km": "$RADPER_VAL",
    "reported_inc_deg": "$INC_VAL",
    "reported_tcm_v_mps": "$TCM_V",
    "reported_tcm_n_mps": "$TCM_N",
    "script_path": "$FINAL_SCRIPT_PATH",
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