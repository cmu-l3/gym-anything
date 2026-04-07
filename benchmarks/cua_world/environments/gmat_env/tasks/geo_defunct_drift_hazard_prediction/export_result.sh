#!/bin/bash
set -euo pipefail

echo "=== Exporting geo_defunct_drift_hazard_prediction results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
GT_DATE=$(cat /tmp/ground_truth_date.txt 2>/dev/null || echo "NOT_FOUND")

SCRIPT_PATH="/home/ga/Documents/missions/defunct_geo_hazard.script"
REPORT_PATH="/home/ga/GMAT_output/hazard_prediction.txt"

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

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Extract the agent's reported date from the hazard prediction file
AGENT_DATE=""
if [ -f "$REPORT_PATH" ]; then
    # Look for a standard date pattern: DD Mon YYYY (e.g., 15 Jun 2026 or 4 Oct 2026)
    AGENT_DATE=$(grep -oP '\b\d{1,2}\s+[A-Za-z]{3}\s+\d{4}\b' "$REPORT_PATH" | head -1 || echo "")
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "gt_date": "$GT_DATE",
    "agent_date": "$AGENT_DATE",
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