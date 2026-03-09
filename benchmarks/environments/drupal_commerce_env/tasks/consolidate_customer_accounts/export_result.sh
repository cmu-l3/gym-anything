#!/bin/bash
# Export script for consolidate_customer_accounts task
echo "=== Exporting consolidate_customer_accounts Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Load stored IDs
UID_OLD=$(cat /tmp/uid_old.txt 2>/dev/null || echo "0")
UID_NEW=$(cat /tmp/uid_new.txt 2>/dev/null || echo "0")
ORDER_ID=$(cat /tmp/target_order_id.txt 2>/dev/null || echo "0")

echo "Checking entities:"
echo "Old UID: $UID_OLD"
echo "New UID: $UID_NEW"
echo "Order ID: $ORDER_ID"

# 1. Check Order Owner
# Get the current UID of the order
CURRENT_ORDER_UID=$(drupal_db_query "SELECT uid FROM commerce_order WHERE order_id=$ORDER_ID")
CURRENT_ORDER_UID=${CURRENT_ORDER_UID:-0}

# 2. Check Old User Status and Existence
# Status 0 = Blocked, 1 = Active
# If empty, user might be deleted
OLD_USER_STATUS=$(drupal_db_query "SELECT status FROM users_field_data WHERE uid=$UID_OLD")
OLD_USER_EXISTS="false"
if [ -n "$OLD_USER_STATUS" ]; then
    OLD_USER_EXISTS="true"
else
    OLD_USER_STATUS="-1" # Deleted
fi

# 3. Check New User Status (should still be active)
NEW_USER_STATUS=$(drupal_db_query "SELECT status FROM users_field_data WHERE uid=$UID_NEW")
NEW_USER_STATUS=${NEW_USER_STATUS:-0}

# 4. Check if order still exists
ORDER_EXISTS="false"
if [ "$CURRENT_ORDER_UID" != "0" ]; then
    ORDER_EXISTS="true"
fi

# Create JSON result
create_result_json /tmp/task_result.json \
    "uid_old=$UID_OLD" \
    "uid_new=$UID_NEW" \
    "order_id=$ORDER_ID" \
    "current_order_uid=$CURRENT_ORDER_UID" \
    "old_user_exists=$OLD_USER_EXISTS" \
    "old_user_status=$OLD_USER_STATUS" \
    "new_user_status=$NEW_USER_STATUS" \
    "order_exists=$ORDER_EXISTS"

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON:"
cat /tmp/task_result.json

echo "=== Export Complete ==="