#!/bin/bash
set -euo pipefail

echo "=== Exporting l1_halo_stationkeeping_design results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/dscovr_skm.script"
REPORT_PATH="/home/ga/GMAT_output/l1_skm_report.txt"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check file existence and timestamps
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

# Parse report values if exists
DV_VAL="0"
TIME_VAL="0"
if [ -f "$REPORT_PATH" ]; then
    # Use case-insensitive grep that ignores exact spacing
    DV_VAL=$(grep -iP 'delta_v_x_m_s.*?\K[0-9\.\+\-eE]+' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    TIME_VAL=$(grep -iP 'time_to_crossing_days.*?\K[0-9\.\+\-eE]+' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "delta_v_x_m_s": "$DV_VAL",
    "time_to_crossing_days": "$TIME_VAL",
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