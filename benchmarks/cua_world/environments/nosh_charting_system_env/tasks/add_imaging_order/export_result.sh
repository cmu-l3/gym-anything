#!/bin/bash
echo "=== Exporting add_imaging_order result ==="

# 1. CAPTURE FINAL SCREENSHOT (Evidence)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. GATHER TASK METADATA
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_order_count.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. QUERY DATABASE FOR ORDERS
# We query the orders table for Robert Murphy (PID 9901)
# We look for orders created AFTER the task started (approximate check via order ID if timestamp is tricky, 
# but NOSH orders usually have a date column).
# We retrieve the most recent order.

echo "Querying database for orders..."

# Get the most recent order for PID 9901
# Note: Adjusting SQL based on assumed NOSH schema columns (orders_id, pid, orders_type, order_description/diagnosis)
# Using `\G` format or JSON output would be nice, but simple tab separated is safer for shell parsing.
# We select pertinent columns.
LAST_ORDER_DATA=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
"SELECT orders_id, orders_type, orders_description, orders_diagnosis, date_ordered \
 FROM orders \
 WHERE pid=9901 \
 ORDER BY orders_id DESC LIMIT 1;" 2>/dev/null)

# Get current count
CURRENT_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
"SELECT COUNT(*) FROM orders WHERE pid=9901 AND (orders_type='rad' OR orders_type='image' OR orders_type LIKE '%rad%');" 2>/dev/null || echo "0")

# 4. PARSE DB RESULTS
ORDER_FOUND="false"
ORDER_ID=""
ORDER_TYPE=""
ORDER_DESC=""
ORDER_REASON=""
ORDER_DATE=""

if [ -n "$LAST_ORDER_DATA" ]; then
    ORDER_FOUND="true"
    ORDER_ID=$(echo "$LAST_ORDER_DATA" | awk '{print $1}')
    ORDER_TYPE=$(echo "$LAST_ORDER_DATA" | awk '{print $2}')
    # Description and Reason might contain spaces, so we use cut carefully or just read the raw line in python later
    # For now, let's grab the raw strings.
    # Re-querying specifically for text fields to handle spaces better
    ORDER_DESC=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT orders_description FROM orders WHERE orders_id=$ORDER_ID;" 2>/dev/null)
    ORDER_REASON=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT orders_diagnosis FROM orders WHERE orders_id=$ORDER_ID;" 2>/dev/null)
    ORDER_DATE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT date_ordered FROM orders WHERE orders_id=$ORDER_ID;" 2>/dev/null)
fi

# 5. CHECK APP STATE
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. CONSTRUCT JSON RESULT
# Use python to safely construct JSON with proper escaping
python3 -c "
import json
import os
import sys

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_count': int('$INITIAL_COUNT'),
    'current_count': int('$CURRENT_COUNT'),
    'order_found': '$ORDER_FOUND' == 'true',
    'last_order': {
        'id': '$ORDER_ID',
        'type': '$ORDER_TYPE',
        'description': '''$ORDER_DESC''',
        'reason': '''$ORDER_REASON''',
        'date': '$ORDER_DATE'
    },
    'app_running': '$APP_RUNNING' == 'true',
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# 7. PERMISSIONS & CLEANUP
chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "Export complete. Result:"
cat /tmp/task_result.json