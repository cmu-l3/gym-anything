#!/bin/bash
set -euo pipefail

echo "=== Exporting mars_aerobraking_analysis results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/missions/mars_aerobraking.script"
RESULTS_PATH="/home/ga/GMAT_output/aerobraking_results.txt"

# Search for alternative script paths if the default isn't found
if [ ! -f "$SCRIPT_PATH" ]; then
    FOUND_SCRIPT=$(find /home/ga/Documents/missions /home/ga/GMAT_output /home/ga/Desktop -name "*.script" -type f -newermt "@$TASK_START" 2>/dev/null | head -1 || echo "")
    if [ -n "$FOUND_SCRIPT" ]; then
        SCRIPT_PATH="$FOUND_SCRIPT"
        echo "Found alternative script at $SCRIPT_PATH"
    fi
fi

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

# Extract values from results file if it exists
INI_APO="0"; FIN_PER="0"; FIN_APO="0"; DV_SAVED="0"
if [ -f "$RESULTS_PATH" ]; then
    INI_APO=$(grep -ioP 'initial_apoapsis_radius_km:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" | head -1 || echo "0")
    FIN_PER=$(grep -ioP 'final_periapsis_radius_km:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" | head -1 || echo "0")
    FIN_APO=$(grep -ioP 'final_apoapsis_radius_km:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" | head -1 || echo "0")
    DV_SAVED=$(grep -ioP 'deltav_saved_mps:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" | head -1 || echo "0")
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
    "initial_apoapsis": "$INI_APO",
    "final_periapsis": "$FIN_PER",
    "final_apoapsis": "$FIN_APO",
    "deltav_saved": "$DV_SAVED",
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