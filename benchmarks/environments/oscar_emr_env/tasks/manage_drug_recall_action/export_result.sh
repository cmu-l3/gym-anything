#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_TICKLER_COUNT=$(cat /tmp/initial_tickler_count.txt 2>/dev/null || echo "0")

# ============================================================
# Query Database for Results
# ============================================================

# 1. Get current tickler count for Maria Santos (ID 501)
CURRENT_TICKLER_COUNT=$(oscar_query "SELECT COUNT(*) FROM tickler WHERE demographic_no='501'" || echo "0")

# 2. Get details of the most recent tickler for Maria Santos
# We fetch: message, priority, status, and creation date
# Note: 'priority' value depends on schema (often 'High' or '1'). We fetch raw value.
LATEST_TICKLER_JSON=$(docker exec oscar-db mysql -u oscar -poscar oscar -N -e \
    "SELECT JSON_OBJECT(
        'tickler_no', tickler_no,
        'message', message,
        'priority', priority,
        'status', status,
        'task_assigned_date', task_assigned_date
     ) 
     FROM tickler 
     WHERE demographic_no='501' 
     ORDER BY tickler_no DESC LIMIT 1;" 2>/dev/null || echo "null")

# ============================================================
# Capture State
# ============================================================
# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if browser is still running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# ============================================================
# Create Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "initial_tickler_count": $INITIAL_TICKLER_COUNT,
    "current_tickler_count": $CURRENT_TICKLER_COUNT,
    "latest_tickler": $LATEST_TICKLER_JSON,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to public location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="