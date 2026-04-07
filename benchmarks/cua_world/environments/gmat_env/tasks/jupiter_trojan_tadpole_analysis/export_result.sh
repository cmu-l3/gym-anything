#!/bin/bash
set -euo pipefail

echo "=== Exporting jupiter_trojan_tadpole_analysis results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/tadpole_mission.script"
RESULTS_PATH="/home/ga/GMAT_output/tadpole_metrics.json"

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

# Parse JSON metrics file if it exists
MIN_DIST="0"
MAX_DIST="0"
if [ -f "$RESULTS_PATH" ]; then
    # Try to extract using python since it's a JSON file
    MIN_DIST=$(python3 -c "import json; print(json.load(open('$RESULTS_PATH')).get('min_jupiter_dist_km', 0))" 2>/dev/null || echo "0")
    MAX_DIST=$(python3 -c "import json; print(json.load(open('$RESULTS_PATH')).get('max_jupiter_dist_km', 0))" 2>/dev/null || echo "0")
    
    # Fallback to grep if python fails
    if [ "$MIN_DIST" = "0" ] || [ -z "$MIN_DIST" ]; then
        MIN_DIST=$(grep -oP '"min_jupiter_dist_km"\s*:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" | head -1 || echo "0")
    fi
    if [ "$MAX_DIST" = "0" ] || [ -z "$MAX_DIST" ]; then
        MAX_DIST=$(grep -oP '"max_jupiter_dist_km"\s*:\s*\K[0-9]+\.?[0-9]*' "$RESULTS_PATH" | head -1 || echo "0")
    fi
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "results_file": $RESULTS_STATS,
    "min_jupiter_dist_km": "$MIN_DIST",
    "max_jupiter_dist_km": "$MAX_DIST",
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