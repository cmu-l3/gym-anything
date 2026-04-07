#!/bin/bash
set -euo pipefail

echo "=== Exporting geo_srp_eccentricity_evolution results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/geo_srp_mission.script"
REPORT_PATH="/home/ga/GMAT_output/geo_srp_report.txt"
ANALYSIS_PATH="/home/ga/GMAT_output/srp_eccentricity_analysis.txt"

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
ANALYSIS_STATS=$(check_file "$ANALYSIS_PATH")

# Count lines in report file to verify it actually ran and recorded data
REPORT_LINE_COUNT=0
if [ -f "$REPORT_PATH" ]; then
    REPORT_LINE_COUNT=$(wc -l < "$REPORT_PATH" || echo "0")
fi

# Run script via GmatConsole if it exists to ensure outputs are fresh/correct
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 180 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_geo_srp.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

# Recheck analysis and report file after execution
ANALYSIS_STATS_RERUN=$(check_file "$ANALYSIS_PATH")
if [ -f "$REPORT_PATH" ]; then
    REPORT_LINE_COUNT=$(wc -l < "$REPORT_PATH" || echo "$REPORT_LINE_COUNT")
fi
REPORT_STATS=$(check_file "$REPORT_PATH")

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "report_line_count": $REPORT_LINE_COUNT,
    "analysis_file": $ANALYSIS_STATS,
    "analysis_file_rerun": $ANALYSIS_STATS_RERUN,
    "console_run_success": "$RUN_SUCCESS",
    "script_path": "$SCRIPT_PATH",
    "report_path": "$REPORT_PATH",
    "analysis_path": "$ANALYSIS_PATH"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="