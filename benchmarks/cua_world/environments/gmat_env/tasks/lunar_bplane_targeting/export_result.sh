#!/bin/bash
set -euo pipefail

echo "=== Exporting lunar_bplane_targeting results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/lunascout_tli.script"
REPORT_PATH="/home/ga/GMAT_output/lunascout_tli_report.txt"

# Capture final visual evidence
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

# Safely extract floating point scientific variables
BURN_V="0"
BURN_N="0"
BDOT_T="0"
BDOT_R="0"

if [ -f "$REPORT_PATH" ]; then
    BURN_V=$(grep -oP 'Converged_Burn_V_kmps:\s*\K[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    BURN_N=$(grep -oP 'Converged_Burn_N_kmps:\s*\K[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    BDOT_T=$(grep -oP 'Achieved_BdotT_km:\s*\K[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    BDOT_R=$(grep -oP 'Achieved_BdotR_km:\s*\K[-+]?[0-9]*\.?[0-9]+(?:[eE][-+]?[0-9]+)?' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")
SPEC_EXISTS=$([ -f "/home/ga/Desktop/lunascout_tli_spec.txt" ] && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "spec_file_exists": $SPEC_EXISTS,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "burn_v": "$BURN_V",
    "burn_n": "$BURN_N",
    "bdot_t": "$BDOT_T",
    "bdot_r": "$BDOT_R",
    "script_path": "$SCRIPT_PATH",
    "report_path": "$REPORT_PATH"
}
EOF

# Move to final destination and set open permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="