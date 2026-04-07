#!/bin/bash
set -euo pipefail

echo "=== Exporting SSO LTAN Maintenance Campaign results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/ltan_campaign.script"
REPORT_PATH="/home/ga/GMAT_output/ltan_drift_report.txt"

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

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

DV_NORMAL="0"
DRIFT_INC="0"
FINAL_LTAN="0"

# Parse the values from the output report if available (handles negative and scientific notation)
if [ -f "$REPORT_PATH" ]; then
    DV_NORMAL=$(grep -ioP 'DeltaV_Normal_kms:\s*\K-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?' "$REPORT_PATH" | head -1 || echo "0")
    DRIFT_INC=$(grep -ioP 'Drift_Inclination_deg:\s*\K-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?' "$REPORT_PATH" | head -1 || echo "0")
    FINAL_LTAN=$(grep -ioP 'Final_LTAN:\s*\K-?[0-9]+\.?[0-9]*([eE][-+]?[0-9]+)?' "$REPORT_PATH" | head -1 || echo "0")
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "deltav_normal_kms": "$DV_NORMAL",
    "drift_inclination_deg": "$DRIFT_INC",
    "final_ltan": "$FINAL_LTAN",
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