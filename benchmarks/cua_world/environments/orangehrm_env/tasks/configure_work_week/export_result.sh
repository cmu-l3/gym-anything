#!/bin/bash
echo "=== Exporting configure_work_week results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ==============================================================================
# CAPTURE FINAL STATE
# ==============================================================================

# 1. Capture Screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Final Work Week Configuration
# We export as a simple JSON object
echo "Querying database for final work week status..."

# Fetch columns (mon..sun)
# Using `mysql -N -B` (No headers, Batch) gives tab-separated values
DB_ROW=$(orangehrm_db_query "SELECT mon, tue, wed, thu, fri, sat, sun FROM ohrm_work_week LIMIT 1;" 2>/dev/null)

# Parse into variables (assuming single row returned)
# Example output: 0	0	0	0	1	4	4
read -r MON TUE WED THU FRI SAT SUN <<< "$DB_ROW"

# Check app running state
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "work_week": {
        "mon": ${MON:-null},
        "tue": ${TUE:-null},
        "wed": ${WED:-null},
        "thu": ${THU:-null},
        "fri": ${FRI:-null},
        "sat": ${SAT:-null},
        "sun": ${SUN:-null}
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="