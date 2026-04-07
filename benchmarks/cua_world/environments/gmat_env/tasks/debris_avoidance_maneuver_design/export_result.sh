#!/bin/bash
set -euo pipefail

echo "=== Exporting debris_avoidance_maneuver_design results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/missions/dam_analysis.script"
REPORT_PATH="/home/ga/GMAT_output/dam_results.txt"

# 1. Take final screenshot
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

# 2. Extract values from report file
DV_V="0"; DV_N="0"; DV_B="0"; TOTAL_DV="100"; MISS_DIST="0"
if [ -f "$REPORT_PATH" ]; then
    DV_V=$(grep -ioP 'Burn_V_mps:\s*\K-?[0-9]+\.?[0-9eE+-]*' "$REPORT_PATH" | head -1 || echo "0")
    DV_N=$(grep -ioP 'Burn_N_mps:\s*\K-?[0-9]+\.?[0-9eE+-]*' "$REPORT_PATH" | head -1 || echo "0")
    DV_B=$(grep -ioP 'Burn_B_mps:\s*\K-?[0-9]+\.?[0-9eE+-]*' "$REPORT_PATH" | head -1 || echo "0")
    TOTAL_DV=$(grep -ioP 'Total_DV_mps:\s*\K[0-9]+\.?[0-9eE+-]*' "$REPORT_PATH" | head -1 || echo "100")
    MISS_DIST=$(grep -ioP 'Miss_Distance_km:\s*\K[0-9]+\.?[0-9eE+-]*' "$REPORT_PATH" | head -1 || echo "0")
fi

# 3. Re-run through GmatConsole for structural validation
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 120 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_output.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# 4. Create JSON output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "burn_v_mps": "$DV_V",
    "burn_n_mps": "$DV_N",
    "burn_b_mps": "$DV_B",
    "total_dv_mps": "$TOTAL_DV",
    "miss_distance_km": "$MISS_DIST",
    "console_run_success": "$RUN_SUCCESS",
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