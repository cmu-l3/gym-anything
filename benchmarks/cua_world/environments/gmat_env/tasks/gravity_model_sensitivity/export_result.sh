#!/bin/bash
set -euo pipefail

echo "=== Exporting gravity_model_sensitivity results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/Documents/missions/gravity_study.script"
REPORT_PATH="/home/ga/GMAT_output/gravity_sensitivity_report.txt"

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

# If the agent used a different script name in the missions folder, try to find it
if [ ! -f "$SCRIPT_PATH" ]; then
    ALT_SCRIPT=$(find /home/ga/Documents/missions /home/ga/GMAT_output -name "*.script" -type f -newermt "@$TASK_START" 2>/dev/null | head -1)
    if [ -n "$ALT_SCRIPT" ]; then
        echo "Found alternative script: $ALT_SCRIPT"
        SCRIPT_PATH="$ALT_SCRIPT"
    fi
fi

SCRIPT_STATS=$(check_file "$SCRIPT_PATH")
REPORT_STATS=$(check_file "$REPORT_PATH")

# Extract values from report file if it exists
J2_DIV="0"
F4_DIV="0"
F12_DIV="0"
if [ -f "$REPORT_PATH" ]; then
    # Use grep to extract decimal values, supporting scientific notation
    J2_DIV=$(grep -ioP 'J2_divergence_km:\s*\K[0-9]+\.?[0-9eE+-]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    F4_DIV=$(grep -ioP '4x4_divergence_km:\s*\K[0-9]+\.?[0-9eE+-]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
    F12_DIV=$(grep -ioP '12x12_divergence_km:\s*\K[0-9]+\.?[0-9eE+-]*' "$REPORT_PATH" 2>/dev/null | head -1 || echo "0")
fi

# Re-run script via GmatConsole (optional anti-gaming check to ensure it compiles/runs)
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 120 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_run.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

# Count GMAT output files generated (excluding the main report)
GMAT_REPORTS_COUNT=$(find /home/ga/GMAT_output -type f -name "*.txt" ! -name "gravity_sensitivity_report.txt" -newermt "@$TASK_START" 2>/dev/null | wc -l)

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "report_file": $REPORT_STATS,
    "script_path": "$SCRIPT_PATH",
    "report_path": "$REPORT_PATH",
    "j2_divergence": "$J2_DIV",
    "f4x4_divergence": "$F4_DIV",
    "f12x12_divergence": "$F12_DIV",
    "gmat_reports_generated": $GMAT_REPORTS_COUNT,
    "console_run_success": "$RUN_SUCCESS"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="