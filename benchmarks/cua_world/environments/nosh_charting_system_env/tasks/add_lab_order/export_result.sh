#!/bin/bash
set -e
echo "=== Exporting task results: add_lab_order ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DURATION=$((TASK_END - TASK_START))

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ============================================================
# Query Database for Verification
# ============================================================

# Get initial count
INITIAL_COUNT=$(cat /tmp/initial_order_count.txt 2>/dev/null || echo "0")

# Get current count for patient 900
CURRENT_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT COUNT(*) FROM orders WHERE pid=900;" 2>/dev/null || echo "0")

# Fetch details of the most recently created order for this patient
# We look for the last ID
LAST_ORDER_JSON=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT JSON_OBJECT(
        'orders_id', orders_id,
        'orders_type', orders_type,
        'orders_description', orders_description,
        'orders_pending', orders_pending,
        'orders_notes', orders_notes,
        'date_ordered', date_ordered
    ) FROM orders WHERE pid=900 ORDER BY orders_id DESC LIMIT 1;" 2>/dev/null || echo "null")

if [ -z "$LAST_ORDER_JSON" ]; then
    LAST_ORDER_JSON="null"
fi

# ============================================================
# Create Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "duration_seconds": $DURATION,
    "initial_order_count": $INITIAL_COUNT,
    "current_order_count": $CURRENT_COUNT,
    "last_order": $LAST_ORDER_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="