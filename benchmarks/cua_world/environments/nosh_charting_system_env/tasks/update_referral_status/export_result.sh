#!/bin/bash
echo "=== Exporting task results ==="

# 1. Basic Info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ORDER_ID=$(cat /tmp/target_order_id.txt 2>/dev/null || echo "0")
PID=$(cat /tmp/target_pid.txt 2>/dev/null || echo "0")

# 2. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Query Database for Final State of the Target Order
echo "Querying database for Order ID: $ORDER_ID"

# Get specific fields
ORDER_STATUS=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT order_status FROM orders WHERE order_id=$ORDER_ID" 2>/dev/null || echo "not_found")

# Check if order was modified (updated_at timestamp if available, otherwise we rely on status change)
# NOSH doesn't always have updated_at on orders table in older versions, so we check status primarily.
# However, we can check if a message/log was generated or if date_completed was set.
DATE_COMPLETED=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT date_completed FROM orders WHERE order_id=$ORDER_ID" 2>/dev/null || echo "NULL")

echo "Final Status: $ORDER_STATUS"
echo "Date Completed: $DATE_COMPLETED"

# 4. Check App State
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")
SCREENSHOT_EXISTS=$([ -f /tmp/task_final.png ] && echo "true" || echo "false")

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_order_id": "$ORDER_ID",
    "target_pid": "$PID",
    "final_order_status": "$ORDER_STATUS",
    "date_completed_db": "$DATE_COMPLETED",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# 6. Save Result Securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="