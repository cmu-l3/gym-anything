#!/bin/bash
set -euo pipefail

echo "=== Exporting leo_drag_makeup_maneuvers results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/missions/drag_makeup.script"
LOG_PATH="/home/ga/GMAT_output/maneuver_log.txt"
SUMMARY_PATH="/home/ga/GMAT_output/maintenance_summary.txt"

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
LOG_STATS=$(check_file "$LOG_PATH")
SUMMARY_STATS=$(check_file "$SUMMARY_PATH")

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Run through GmatConsole if script exists to verify it runs without crashing
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Testing script via GmatConsole..."
    timeout 300 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_makeup.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

# Re-check output files in case the agent relied on the verifier to run it
SUMMARY_STATS_RERUN=$(check_file "$SUMMARY_PATH")
LOG_STATS_RERUN=$(check_file "$LOG_PATH")

# Extract summary metrics from the final file
TOTAL_BURNS="0"
TOTAL_DV="0"
AVG_DV="0"
AVG_INT="0"
FINAL_SMA="0"

if [ -f "$SUMMARY_PATH" ]; then
    TOTAL_BURNS=$(grep -iP 'total_burns:\s*\K[0-9]+' "$SUMMARY_PATH" | head -1 || echo "0")
    TOTAL_DV=$(grep -iP 'total_deltav_ms:\s*\K[0-9]+\.?[0-9]*' "$SUMMARY_PATH" | head -1 || echo "0")
    AVG_DV=$(grep -iP 'avg_deltav_per_burn_ms:\s*\K[0-9]+\.?[0-9]*' "$SUMMARY_PATH" | head -1 || echo "0")
    AVG_INT=$(grep -iP 'avg_maneuver_interval_days:\s*\K[0-9]+\.?[0-9]*' "$SUMMARY_PATH" | head -1 || echo "0")
    FINAL_SMA=$(grep -iP 'final_sma_km:\s*\K[0-9]+\.?[0-9]*' "$SUMMARY_PATH" | head -1 || echo "0")
fi

# Determine if the script actually contains looping logic
HAS_LOOP="false"
HAS_BURN="false"
if [ -f "$SCRIPT_PATH" ]; then
    grep -qiE 'While |If ' "$SCRIPT_PATH" && HAS_LOOP="true" || true
    grep -q "Create ImpulsiveBurn" "$SCRIPT_PATH" && HAS_BURN="true" || true
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "log_file": $LOG_STATS,
    "log_file_rerun": $LOG_STATS_RERUN,
    "summary_file": $SUMMARY_STATS,
    "summary_file_rerun": $SUMMARY_STATS_RERUN,
    "console_run_success": "$RUN_SUCCESS",
    "has_loop_logic": $HAS_LOOP,
    "has_burn_definition": $HAS_BURN,
    "total_burns": "$TOTAL_BURNS",
    "total_deltav_ms": "$TOTAL_DV",
    "avg_deltav_per_burn_ms": "$AVG_DV",
    "avg_interval_days": "$AVG_INT",
    "final_sma_km": "$FINAL_SMA",
    "script_path": "$SCRIPT_PATH",
    "summary_path": "$SUMMARY_PATH"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="