#!/bin/bash
set -euo pipefail

echo "=== Exporting leo_rendezvous_phasing results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/missions/rendezvous_phasing.script"
RESULTS_PATH="/home/ga/GMAT_output/rendezvous_results.txt"

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

# Re-run script via GmatConsole
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 180 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_rendezvous.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

RESULTS_STATS_RERUN=$(check_file "$RESULTS_PATH")

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Extract values from results file
DV1="0"; DV2="0"; PHASE_TIME="0"; SEP="0"; ALT="0"
if [ -f "$RESULTS_PATH" ]; then
    DV1=$(grep -oP 'DeltaV1_mps:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    DV2=$(grep -oP 'DeltaV2_mps:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    PHASE_TIME=$(grep -oP 'PhasingTime_hours:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    SEP=$(grep -oP 'FinalSeparation_km:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    ALT=$(grep -oP 'CHASER_final_altitude_km:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
fi

# Check script has two spacecraft and two burns
HAS_CHIEF="false"
HAS_CHASER="false"
TWO_BURNS="false"
if [ -f "$SCRIPT_PATH" ]; then
    grep -q "CHIEF\|Chief" "$SCRIPT_PATH" 2>/dev/null && HAS_CHIEF="true" || true
    grep -q "CHASER\|Chaser" "$SCRIPT_PATH" 2>/dev/null && HAS_CHASER="true" || true
    BURN_COUNT=$(grep -c "Create ImpulsiveBurn\|Maneuver\b" "$SCRIPT_PATH" 2>/dev/null || echo "0")
    [ "$BURN_COUNT" -ge 2 ] && TWO_BURNS="true" || true
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
    "has_chief_spacecraft": $HAS_CHIEF,
    "has_chaser_spacecraft": $HAS_CHASER,
    "has_two_burns": $TWO_BURNS,
    "deltav1_mps": "$DV1",
    "deltav2_mps": "$DV2",
    "phasing_time_hours": "$PHASE_TIME",
    "final_separation_km": "$SEP",
    "chaser_final_altitude_km": "$ALT",
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
