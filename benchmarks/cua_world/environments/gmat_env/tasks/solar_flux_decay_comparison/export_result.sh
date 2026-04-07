#!/bin/bash
set -euo pipefail

echo "=== Exporting solar_flux_decay_comparison results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/missions/solar_flux_study.script"
ANALYSIS_PATH="/home/ga/GMAT_output/solar_flux_analysis.txt"

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
ANALYSIS_STATS=$(check_file "$ANALYSIS_PATH")

# Re-run script via GmatConsole
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 300 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_solar.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

# Re-check analysis file after re-run
ANALYSIS_STATS_RERUN=$(check_file "$ANALYSIS_PATH")

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Extract values from analysis file
SMA_Q="0"; SMA_M="0"; SMA_A="0"
DECAY_Q="0"; DECAY_M="0"; DECAY_A="0"
RATIO="0"
if [ -f "$ANALYSIS_PATH" ]; then
    SMA_Q=$(grep -oP 'Scenario_1_QuietSun_SMA_final_km:\s*\K[0-9]+\.?[0-9]*' "$ANALYSIS_PATH" 2>/dev/null | head -1 || echo "0")
    SMA_M=$(grep -oP 'Scenario_2_ModerateSun_SMA_final_km:\s*\K[0-9]+\.?[0-9]*' "$ANALYSIS_PATH" 2>/dev/null | head -1 || echo "0")
    SMA_A=$(grep -oP 'Scenario_3_ActiveSun_SMA_final_km:\s*\K[0-9]+\.?[0-9]*' "$ANALYSIS_PATH" 2>/dev/null | head -1 || echo "0")
    DECAY_Q=$(grep -oP 'SMA_decay_quiet_km:\s*\K[0-9]+\.?[0-9]*' "$ANALYSIS_PATH" 2>/dev/null | head -1 || echo "0")
    DECAY_M=$(grep -oP 'SMA_decay_moderate_km:\s*\K[0-9]+\.?[0-9]*' "$ANALYSIS_PATH" 2>/dev/null | head -1 || echo "0")
    DECAY_A=$(grep -oP 'SMA_decay_active_km:\s*\K[0-9]+\.?[0-9]*' "$ANALYSIS_PATH" 2>/dev/null | head -1 || echo "0")
    RATIO=$(grep -oP 'Decay_ratio_active_to_quiet:\s*\K[0-9]+\.?[0-9]*' "$ANALYSIS_PATH" 2>/dev/null | head -1 || echo "0")
fi

# Count how many F10.7 scenarios are in the script (must be 3)
SCENARIO_COUNT="0"
if [ -f "$SCRIPT_PATH" ]; then
    SCENARIO_COUNT=$(grep -c "F107\s*=" "$SCRIPT_PATH" 2>/dev/null || echo "0")
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "analysis_file": $ANALYSIS_STATS,
    "analysis_file_rerun": $ANALYSIS_STATS_RERUN,
    "console_run_success": "$RUN_SUCCESS",
    "scenario_count_in_script": $SCENARIO_COUNT,
    "sma_final_quiet_km": "$SMA_Q",
    "sma_final_moderate_km": "$SMA_M",
    "sma_final_active_km": "$SMA_A",
    "decay_quiet_km": "$DECAY_Q",
    "decay_moderate_km": "$DECAY_M",
    "decay_active_km": "$DECAY_A",
    "ratio_active_to_quiet": "$RATIO",
    "script_path": "$SCRIPT_PATH",
    "analysis_path": "$ANALYSIS_PATH"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="
