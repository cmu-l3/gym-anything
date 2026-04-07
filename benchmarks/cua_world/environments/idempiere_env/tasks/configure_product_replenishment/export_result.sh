#!/bin/bash
set -e
echo "=== Exporting Configure Product Replenishment results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record IDs
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLIENT_ID=$(get_gardenworld_client_id)

# ----------------------------------------------------------------
# 1. Query the Replenishment Table
# ----------------------------------------------------------------
# We join with Product and Warehouse to ensure we get the right record based on names
# We select the specific fields we need to verify

QUERY="
SELECT 
    r.m_replenish_id,
    r.replenishtype,
    r.level_min,
    r.level_max,
    extract(epoch from r.created) as created_ts,
    extract(epoch from r.updated) as updated_ts
FROM m_replenish r
JOIN m_product p ON r.m_product_id = p.m_product_id
JOIN m_warehouse w ON r.m_warehouse_id = w.m_warehouse_id
WHERE p.name = 'Elm Tree'
  AND w.name = 'HQ Warehouse'
  AND r.ad_client_id = $CLIENT_ID
"

# Execute query - output as pipe-separated values
RESULT_ROW=$(idempiere_query "$QUERY" 2>/dev/null || echo "")

# Initialize result variables
RECORD_FOUND="false"
REPLENISH_TYPE=""
LEVEL_MIN="0"
LEVEL_MAX="0"
CREATED_TS="0"
UPDATED_TS="0"

if [ -n "$RESULT_ROW" ]; then
    RECORD_FOUND="true"
    # Parse pipe-separated values (default psql output for -A)
    # Format: id|type|min|max|created|updated
    REPLENISH_TYPE=$(echo "$RESULT_ROW" | cut -d'|' -f2)
    LEVEL_MIN=$(echo "$RESULT_ROW" | cut -d'|' -f3)
    LEVEL_MAX=$(echo "$RESULT_ROW" | cut -d'|' -f4)
    CREATED_TS=$(echo "$RESULT_ROW" | cut -d'|' -f5 | cut -d'.' -f1) # remove subseconds
    UPDATED_TS=$(echo "$RESULT_ROW" | cut -d'|' -f6 | cut -d'.' -f1)
fi

# ----------------------------------------------------------------
# 2. Capture Final State
# ----------------------------------------------------------------
take_screenshot /tmp/task_final.png

# Check if browser is running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# ----------------------------------------------------------------
# 3. Create JSON Result
# ----------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "record_found": $RECORD_FOUND,
    "replenish_type": "$REPLENISH_TYPE",
    "level_min": ${LEVEL_MIN:-0},
    "level_max": ${LEVEL_MAX:-0},
    "created_ts": ${CREATED_TS:-0},
    "updated_ts": ${UPDATED_TS:-0},
    "task_start_ts": $TASK_START,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="