#!/bin/bash
set -euo pipefail

echo "=== Exporting artemis_hls_nrho_to_llo_transfer results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/hls_transfer_script.script"
RESULTS_PATH="/home/ga/GMAT_output/hls_transfer_results.txt"

# Capture final visual state
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
RESULTS_STATS=$(check_file "$RESULTS_PATH")

# Parse out variables from the results file if they exist
B1_DV="0"
B2_DV="0"
TOT_DV="0"
F_SMA="0"
F_ECC="1"

if [ -f "$RESULTS_PATH" ]; then
    B1_DV=$(grep -ioP 'Burn1_DeltaV_mps:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    B2_DV=$(grep -ioP 'Burn2_DeltaV_mps:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    TOT_DV=$(grep -ioP 'Total_DeltaV_mps:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    F_SMA=$(grep -ioP 'Final_SMA_km:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    F_ECC=$(grep -ioP 'Final_ECC:\s*\K[0-9]+\.?[0-9e+-]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "1")
fi

# Check for DC targeting commands in the script text
DC_USED="false"
if [ -f "$SCRIPT_PATH" ]; then
    if grep -q "DifferentialCorrector\|Target\|Vary\|Achieve" "$SCRIPT_PATH" 2>/dev/null; then
        DC_USED="true"
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
    "results_file": $RESULTS_STATS,
    "dc_used_in_script": $DC_USED,
    "burn1_dv_mps": "$B1_DV",
    "burn2_dv_mps": "$B2_DV",
    "total_dv_mps": "$TOT_DV",
    "final_sma_km": "$F_SMA",
    "final_ecc": "$F_ECC",
    "script_path": "$SCRIPT_PATH",
    "results_path": "$RESULTS_PATH"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="