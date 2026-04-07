#!/bin/bash
set -euo pipefail

echo "=== Exporting transfer_strategy_tradeoff results ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

REPORT_PATH="/home/ga/GMAT_output/transfer_trade_study.txt"
MISSIONS_DIR="/home/ga/Documents/missions"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if report exists
REPORT_EXISTS="false"
REPORT_SIZE="0"
REPORT_CREATED_DURING="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH")
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$REPORT_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
    # Copy report to tmp for verifier python script to easily access
    cp "$REPORT_PATH" /tmp/report.txt
else
    echo "" > /tmp/report.txt
fi

# Gather all script files in the missions directory
SCRIPT_EXISTS="false"
SCRIPT_COUNT=$(find "$MISSIONS_DIR" -maxdepth 1 -name "*.script" | wc -l)
SCRIPT_CREATED_DURING="false"

if [ "$SCRIPT_COUNT" -gt 0 ]; then
    SCRIPT_EXISTS="true"
    # Find the newest script file modification time
    NEWEST_SCRIPT=$(find "$MISSIONS_DIR" -maxdepth 1 -name "*.script" -printf '%T@\n' | sort -n | tail -1 | cut -f1 -d".")
    if [ -n "$NEWEST_SCRIPT" ] && [ "$NEWEST_SCRIPT" -ge "$TASK_START" ]; then
        SCRIPT_CREATED_DURING="true"
    fi
    
    # Concatenate all scripts to a single file for the verifier to analyze
    cat "$MISSIONS_DIR"/*.script > /tmp/all_scripts.txt 2>/dev/null || echo "" > /tmp/all_scripts.txt
else
    echo "" > /tmp/all_scripts.txt
fi

APP_RUNNING=$(pgrep -f "GMAT" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "report_file": {
        "exists": $REPORT_EXISTS,
        "size": $REPORT_SIZE,
        "created_during_task": $REPORT_CREATED_DURING
    },
    "script_file": {
        "exists": $SCRIPT_EXISTS,
        "count": $SCRIPT_COUNT,
        "created_during_task": $SCRIPT_CREATED_DURING
    }
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
chmod 666 /tmp/report.txt 2>/dev/null || true
chmod 666 /tmp/all_scripts.txt 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json
echo "=== Export Done ==="