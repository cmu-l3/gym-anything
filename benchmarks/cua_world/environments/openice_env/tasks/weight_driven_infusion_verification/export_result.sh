#!/bin/bash
echo "=== Exporting Weight-Driven Infusion Verification Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get OpenICE log data (new lines only)
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

# --- Evidence Extraction ---

# 1. Device Creation Evidence
# Search for Scale
SCALE_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "Scale|Mass|Weight" || \
   DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "Scale|Mass"; then
    SCALE_CREATED="true"
fi

# Search for Pump
PUMP_CREATED="false"
if echo "$NEW_LOG" | grep -qiE "Infusion|Pump" || \
   DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qiE "Infusion|Pump"; then
    PUMP_CREATED="true"
fi

# 2. Weight Setting Evidence
# Try to find the last published weight in logs if available
# The simulated scale often logs "metric ... value changed to X"
LAST_LOGGED_WEIGHT=""
# Look for numbers near "kg" or "Mass" in the log
# This is a heuristic; the verifier will also check the user's report
LAST_LOGGED_WEIGHT=$(echo "$NEW_LOG" | grep -i "Mass" | grep -oE "[0-9]+\.?[0-9]*" | tail -1)

# 3. Report File Analysis
REPORT_PATH="/home/ga/Desktop/dose_verification.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 1000) # Limit size
fi

# 4. App Running Check
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# Create result JSON
create_result_json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "scale_created": $SCALE_CREATED,
    "pump_created": $PUMP_CREATED,
    "last_logged_weight_heuristic": "$LAST_LOGGED_WEIGHT",
    "report_exists": $REPORT_EXISTS,
    "report_content": "$(escape_json_value "$REPORT_CONTENT")",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "=== Export Complete ==="
cat /tmp/task_result.json