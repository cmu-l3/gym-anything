#!/bin/bash
set -e
echo "=== Exporting create_warehouse_locators results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Query Database for Results
echo "--- Querying iDempiere Database ---"

# Get Warehouse ID again
WAREHOUSE_ID=$(idempiere_query "SELECT m_warehouse_id FROM m_warehouse WHERE name LIKE 'HQ%' LIMIT 1" 2>/dev/null)

# Get current count
CURRENT_COUNT=$(idempiere_query "SELECT COUNT(*) FROM m_locator WHERE m_warehouse_id=$WAREHOUSE_ID AND isactive='Y'" 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_locator_count.txt 2>/dev/null || echo "0")

# Check specific locators
# We return JSON array of found locators matching our target values
# Fields: value, x, y, z, created, isactive
LOCATORS_JSON=$(idempiere_query "
SELECT row_to_json(t) FROM (
    SELECT value, x, y, z, created, isactive 
    FROM m_locator 
    WHERE m_warehouse_id=$WAREHOUSE_ID 
      AND value IN ('OV-01-01', 'OV-01-02', 'OV-01-03')
      AND isactive='Y'
) t
" 2>/dev/null | jq -s '.' || echo "[]")

# 3. Check application state
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "warehouse_id": "${WAREHOUSE_ID}",
    "initial_count": ${INITIAL_COUNT},
    "current_count": ${CURRENT_COUNT},
    "found_locators": ${LOCATORS_JSON},
    "app_running": ${APP_RUNNING},
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Move to final location (handle permissions)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="