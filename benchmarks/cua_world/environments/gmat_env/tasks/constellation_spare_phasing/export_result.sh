#!/bin/bash
set -euo pipefail

echo "=== Exporting constellation_spare_phasing results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/spare_phasing.script"
RESULTS_PATH="/home/ga/GMAT_output/phasing_results.txt"

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

# Parse variables from results file if it exists
WAIT_TIME="0"
DV1="0"
DV2="0"
TOTAL_DV="0"
PHASE_DIFF="180.0"

if [ -f "$RESULTS_PATH" ]; then
    WAIT_TIME=$(grep -oP 'Wait_Time_Hours:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    DV1=$(grep -oP 'Burn1_DeltaV_ms:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    DV2=$(grep -oP 'Burn2_DeltaV_ms:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    TOTAL_DV=$(grep -oP 'Total_DeltaV_ms:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    PHASE_DIFF=$(grep -oP 'Final_Phase_Diff_deg:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "180.0")
fi

# Re-run the script in console mode to confirm it evaluates
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 180 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_phasing.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

RESULTS_STATS_RERUN=$(check_file "$RESULTS_PATH")
APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Inspect Script Structure
HAS_TARGET="false"
HAS_SPARE="false"
BURN_COUNT="0"

if [ -f "$SCRIPT_PATH" ]; then
    grep -qi "TARGET\|SLOT" "$SCRIPT_PATH" 2>/dev/null && HAS_TARGET="true" || true
    grep -qi "SPARE" "$SCRIPT_PATH" 2>/dev/null && HAS_SPARE="true" || true
    BURN_COUNT=$(grep -c "Create ImpulsiveBurn\|Maneuver" "$SCRIPT_PATH" 2>/dev/null || echo "0")
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "results_file": $RESULTS_STATS,
    "results_file_rerun": $RESULTS_STATS_RERUN,
    "console_run_success": "$RUN_SUCCESS",
    "has_target_sc": $HAS_TARGET,
    "has_spare_sc": $HAS_SPARE,
    "burn_count": $BURN_COUNT,
    "wait_time_hours": "$WAIT_TIME",
    "burn1_dv_ms": "$DV1",
    "burn2_dv_ms": "$DV2",
    "total_dv_ms": "$TOTAL_DV",
    "final_phase_diff_deg": "$PHASE_DIFF",
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