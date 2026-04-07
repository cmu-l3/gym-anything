#!/bin/bash
set -euo pipefail

echo "=== Exporting sar_ground_track_targeting results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/missions/sar_targeting.script"
REPORT_PATH="/home/ga/GMAT_output/overflight_report.txt"

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

# Re-run the script through GmatConsole for anti-gaming verification
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 180 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_output.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

REPORT_STATS_RERUN=$(check_file "$REPORT_PATH")
APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Extract values from report file
DV_VAL="0"
LAT_VAL="0"
LON_VAL="0"

if [ -f "$REPORT_PATH" ]; then
    DV_VAL=$(grep -oP 'maneuver_dv_m_s:\s*\K[-+]?[0-9]*\.?[0-9eE+-]+' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    LAT_VAL=$(grep -oP 'final_latitude_deg:\s*\K[-+]?[0-9]*\.?[0-9eE+-]+' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    LON_VAL=$(grep -oP 'final_longitude_deg:\s*\K[-+]?[0-9]*\.?[0-9eE+-]+' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
fi

# Check for DC usage in the script
DC_USED="false"
if [ -f "$SCRIPT_PATH" ]; then
    grep -q "Target\|Achieve\|Vary\|DifferentialCorrector" "$SCRIPT_PATH" 2>/dev/null && DC_USED="true" || DC_USED="false"
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
    "dc_used_in_script": $DC_USED,
    "maneuver_dv_m_s": "$DV_VAL",
    "final_latitude_deg": "$LAT_VAL",
    "final_longitude_deg": "$LON_VAL",
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