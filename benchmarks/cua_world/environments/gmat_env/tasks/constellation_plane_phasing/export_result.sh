#!/bin/bash
set -euo pipefail

echo "=== Exporting constellation_plane_phasing results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

RESULTS_PATH="/home/ga/GMAT_output/phasing_results.txt"

# Search for the script in case the agent named it differently
SCRIPT_PATH="/home/ga/Documents/missions/plane_phasing.script"
if [ ! -f "$SCRIPT_PATH" ]; then
    # Look for any recently modified script
    RECENT_SCRIPT=$(find /home/ga/Documents/missions /home/ga/GMAT_output -name "*.script" -type f -newermt "@$TASK_START" 2>/dev/null | head -1 || echo "")
    if [ -n "$RECENT_SCRIPT" ]; then
        SCRIPT_PATH="$RECENT_SCRIPT"
        echo "Found recently created script at $SCRIPT_PATH"
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

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Extract values from results file
DUR_DAYS="0"
TOT_DV="0"
RAAN_DIFF="0"

if [ -f "$RESULTS_PATH" ]; then
    DUR_DAYS=$(grep -i -oP 'Drift_Duration_Days:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    TOT_DV=$(grep -i -oP 'Total_DeltaV_ms:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    RAAN_DIFF=$(grep -i -oP 'Final_RAAN_Diff_deg:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
fi

# Basic static analysis of the script to verify structure
SC_COUNT=0
BURN_COUNT=0
if [ -f "$SCRIPT_PATH" ]; then
    SC_COUNT=$(grep -c -i "Create Spacecraft" "$SCRIPT_PATH" 2>/dev/null || echo "0")
    BURN_COUNT=$(grep -c -i "Create ImpulsiveBurn" "$SCRIPT_PATH" 2>/dev/null || echo "0")
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "results_file": $RESULTS_STATS,
    "spacecraft_count": $SC_COUNT,
    "burn_count": $BURN_COUNT,
    "drift_duration_days": "$DUR_DAYS",
    "total_deltav_ms": "$TOT_DV",
    "final_raan_diff_deg": "$RAAN_DIFF",
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