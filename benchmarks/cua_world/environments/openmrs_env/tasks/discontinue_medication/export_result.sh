#!/bin/bash
# Export: discontinue_medication task
# Verifies that the specific Aspirin order has been discontinued.

set -e
echo "=== Exporting discontinue_medication results ==="
source /workspace/scripts/task_utils.sh

# 1. Read Task Context
if [ ! -f /tmp/task_context.json ]; then
    echo "ERROR: Task context missing!"
    exit 1
fi

PATIENT_UUID=$(jq -r '.patient_uuid' /tmp/task_context.json)
TARGET_ORDER_UUID=$(jq -r '.target_order_uuid' /tmp/task_context.json)
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END_TIME=$(date +%s)

echo "Checking status for Order: $TARGET_ORDER_UUID"

# 2. Database Verification
# We check two things:
# A) The original order (NEW) should now have a date_stopped.
# B) There should be a new order (DISCONTINUE) linked to the original.

# Query DB for the original order status
# Note: In OpenMRS DB, 'orders' table has date_stopped.
ORIGINAL_ORDER_STATUS=$(omrs_db_query "SELECT date_stopped FROM orders WHERE uuid='$TARGET_ORDER_UUID' LIMIT 1;")

# Query DB for the discontinuation order
# Look for an order where previous_order_id points to our target and action is DISCONTINUE (action=3 usually, or enum)
# But simpler to check via REST or just join in SQL.
# 'order_action' column is usually string 'DISCONTINUE' in newer OpenMRS, or mapped enum.
DISCONTINUE_ORDER_EXISTS=$(omrs_db_query "SELECT count(*) FROM orders WHERE previous_order_id = (SELECT order_id FROM orders WHERE uuid='$TARGET_ORDER_UUID') AND order_action='DISCONTINUE';")

# 3. REST API Verification (Double Check)
# Check if Aspirin is still in active list
IS_ACTIVE_REST=$(omrs_get "/order?patient=$PATIENT_UUID&status=active&v=default" | \
    python3 -c "import sys,json; r=json.load(sys.stdin); print('true' if any(o['uuid'] == '$TARGET_ORDER_UUID' for o in r.get('results',[])) else 'false')" 2>/dev/null || echo "false")

# 4. Anti-Gaming Timestamp Check
# The date_stopped should be > TASK_START_TIME (converted to DB format if needed, but here we just check if it's set)
# We can check the date_created of the DISCONTINUE order.
DISCONTINUE_TIMESTAMP=$(omrs_db_query "SELECT UNIX_TIMESTAMP(date_created) FROM orders WHERE previous_order_id = (SELECT order_id FROM orders WHERE uuid='$TARGET_ORDER_UUID') AND order_action='DISCONTINUE' LIMIT 1;")
if [ -z "$DISCONTINUE_TIMESTAMP" ]; then DISCONTINUE_TIMESTAMP=0; fi

ACTION_AFTER_START="false"
if [ "$DISCONTINUE_TIMESTAMP" -gt "$TASK_START_TIME" ]; then
    ACTION_AFTER_START="true"
fi

# 5. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Generate Result JSON
cat > /tmp/task_result.json <<EOF
{
  "original_order_uuid": "$TARGET_ORDER_UUID",
  "original_order_stopped": $([ "$ORIGINAL_ORDER_STATUS" != "NULL" ] && echo "true" || echo "false"),
  "discontinue_order_db_count": ${DISCONTINUE_ORDER_EXISTS:-0},
  "is_active_in_rest": $IS_ACTIVE_REST,
  "action_performed_after_start": $ACTION_AFTER_START,
  "task_start_ts": $TASK_START_TIME,
  "action_ts": $DISCONTINUE_TIMESTAMP,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Fix permissions
chmod 666 /tmp/task_result.json

echo "Result Exported:"
cat /tmp/task_result.json
echo "=== Export Complete ==="