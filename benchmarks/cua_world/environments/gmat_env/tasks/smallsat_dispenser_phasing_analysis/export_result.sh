#!/bin/bash
set -euo pipefail

echo "=== Exporting smallsat_dispenser_phasing_analysis results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/missions/dispenser_mission.script"
REPORT_PATH="/home/ga/GMAT_output/dispenser_separation_report.txt"

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

# Re-run the corrected script through GmatConsole to get actual outputs
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 180 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_output.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

REPORT_STATS_RERUN=$(check_file "$REPORT_PATH")

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Parse report
SMA_A="0"; SMA_B="0"; SMA_C="0"; SMA_D="0"
ANG_AB="0"; ANG_AC="0"; ANG_AD="0"

if [ -f "$REPORT_PATH" ]; then
    # Allows for negative angles incase agent subtracts in reverse, verifier takes abs()
    SMA_A=$(grep -oP 'sat_A_sma_km:\s*\K-?[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    SMA_B=$(grep -oP 'sat_B_sma_km:\s*\K-?[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    SMA_C=$(grep -oP 'sat_C_sma_km:\s*\K-?[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    SMA_D=$(grep -oP 'sat_D_sma_km:\s*\K-?[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    
    ANG_AB=$(grep -oP 'angle_A_to_B_deg:\s*\K-?[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    ANG_AC=$(grep -oP 'angle_A_to_C_deg:\s*\K-?[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    ANG_AD=$(grep -oP 'angle_A_to_D_deg:\s*\K-?[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
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
    "sma_A_km": "$SMA_A",
    "sma_B_km": "$SMA_B",
    "sma_C_km": "$SMA_C",
    "sma_D_km": "$SMA_D",
    "angle_A_to_B_deg": "$ANG_AB",
    "angle_A_to_C_deg": "$ANG_AC",
    "angle_A_to_D_deg": "$ANG_AD",
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