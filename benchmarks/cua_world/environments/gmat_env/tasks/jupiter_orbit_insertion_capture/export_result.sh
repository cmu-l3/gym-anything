#!/bin/bash
set -euo pipefail

echo "=== Exporting jupiter_orbit_insertion_capture results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/missions/joi_sim.script"
RESULTS_PATH="/home/ga/GMAT_output/joi_results.txt"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Function to check file existence and modification time securely
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

# If the agent saved the script in GMAT_output instead, fall back to it
if [ ! -f "$SCRIPT_PATH" ] && [ -f "/home/ga/GMAT_output/joi_sim.script" ]; then
    SCRIPT_PATH="/home/ga/GMAT_output/joi_sim.script"
fi

SCRIPT_STATS=$(check_file "$SCRIPT_PATH")
RESULTS_STATS=$(check_file "$RESULTS_PATH")

# Extract values from results file if it exists
DV_VAL="0"
SMA_VAL="0"
ECC_VAL="0"

if [ -f "$RESULTS_PATH" ]; then
    DV_VAL=$(grep -oP 'required_deltav_m_s:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    SMA_VAL=$(grep -oP 'final_sma_km:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
    ECC_VAL=$(grep -oP 'final_eccentricity:\s*\K-?[0-9]+\.?[0-9]*' "$RESULTS_PATH" 2>/dev/null | head -1 || echo "0")
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Assemble JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "results_file": $RESULTS_STATS,
    "required_deltav_m_s": "$DV_VAL",
    "final_sma_km": "$SMA_VAL",
    "final_eccentricity": "$ECC_VAL",
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