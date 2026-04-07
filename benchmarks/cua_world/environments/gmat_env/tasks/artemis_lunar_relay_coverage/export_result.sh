#!/bin/bash
set -euo pipefail

echo "=== Exporting artemis_lunar_relay_coverage results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

SCRIPT_PATH="/home/ga/GMAT_output/artemis_relay.script"
SUMMARY_PATH="/home/ga/GMAT_output/relay_summary.txt"

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
SUMMARY_STATS=$(check_file "$SUMMARY_PATH")

# Extract parameters from the summary file safely
SMA_VAL="0"
ECC_VAL="0"
INC_VAL="0"
CONTACT_VAL="0"

if [ -f "$SUMMARY_PATH" ]; then
    SMA_VAL=$(grep -oP 'SMA_km:\s*\K[0-9]+\.?[0-9]*' "$SUMMARY_PATH" 2>/dev/null | head -1 || echo "0")
    ECC_VAL=$(grep -oP 'ECC:\s*\K[0-9]+\.?[0-9]*' "$SUMMARY_PATH" 2>/dev/null | head -1 || echo "0")
    INC_VAL=$(grep -oP 'INC_deg:\s*\K[0-9]+\.?[0-9]*' "$SUMMARY_PATH" 2>/dev/null | head -1 || echo "0")
    CONTACT_VAL=$(grep -oP 'max_continuous_contact_hours:\s*\K[0-9]+\.?[0-9]*' "$SUMMARY_PATH" 2>/dev/null | head -1 || echo "0")
fi

# Re-run the script through GmatConsole (if script exists) to verify it compiles and runs
CONSOLE=$(find_gmat_console 2>/dev/null || echo "")
RUN_SUCCESS="false"
if [ -n "$CONSOLE" ] && [ -f "$SCRIPT_PATH" ]; then
    echo "Re-running script via GmatConsole..."
    timeout 180 "$CONSOLE" --run "$SCRIPT_PATH" > /tmp/gmat_console_output.txt 2>&1 && RUN_SUCCESS="true" || RUN_SUCCESS="false"
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "script_file": $SCRIPT_STATS,
    "summary_file": $SUMMARY_STATS,
    "summary_sma": "$SMA_VAL",
    "summary_ecc": "$ECC_VAL",
    "summary_inc": "$INC_VAL",
    "summary_contact": "$CONTACT_VAL",
    "console_run_success": "$RUN_SUCCESS",
    "script_path": "$SCRIPT_PATH",
    "summary_path": "$SUMMARY_PATH"
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="