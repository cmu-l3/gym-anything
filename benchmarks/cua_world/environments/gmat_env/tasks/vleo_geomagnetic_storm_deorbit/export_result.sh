#!/bin/bash
set -euo pipefail

echo "=== Exporting vleo_geomagnetic_storm_deorbit results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/storm_decay_simulation.script"
REPORT_PATH="/home/ga/GMAT_output/storm_survival_report.txt"

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

NOMINAL_DAYS="-1"; STORM_DAYS="-1"
NOMINAL_ALT="-1"; STORM_ALT="-1"

if [ -f "$REPORT_PATH" ]; then
    NOMINAL_DAYS=$(grep -ioP 'nominal_survival_days:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "-1")
    STORM_DAYS=$(grep -ioP 'storm_survival_days:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "-1")
    NOMINAL_ALT=$(grep -ioP 'nominal_final_alt_km:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "-1")
    STORM_ALT=$(grep -ioP 'storm_final_alt_km:\s*\K[0-9]+\.?[0-9]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "-1")
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "nominal_survival_days": "$NOMINAL_DAYS",
    "storm_survival_days": "$STORM_DAYS",
    "nominal_final_alt_km": "$NOMINAL_ALT",
    "storm_final_alt_km": "$STORM_ALT",
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