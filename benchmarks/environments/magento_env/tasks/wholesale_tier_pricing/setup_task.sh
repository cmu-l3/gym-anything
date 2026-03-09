#!/bin/bash
# Setup script for Wholesale Tier Pricing task

echo "=== Setting up Wholesale Tier Pricing Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Admin credentials
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"

# 1. Clean up previous runs (idempotency)
# Remove the group if it exists to ensure the agent actually creates it
# Note: In a real env we might check for dependencies, but for this task we assume it's safe to reset
echo "Checking for existing 'Wholesale Buyers' group..."
EXISTING_GROUP_ID=$(magento_query "SELECT customer_group_id FROM customer_group WHERE LOWER(TRIM(customer_group_code))='wholesale buyers'" 2>/dev/null | tail -1 | tr -d '[:space:]')

if [ -n "$EXISTING_GROUP_ID" ]; then
    echo "Removing existing group (ID: $EXISTING_GROUP_ID) to reset task..."
    # Delete tier prices associated with this group first
    magento_query_headers "DELETE FROM catalog_product_entity_tier_price WHERE customer_group_id=$EXISTING_GROUP_ID" 2>/dev/null
    # Reset customer to General group (ID 1)
    magento_query_headers "UPDATE customer_entity SET group_id=1 WHERE group_id=$EXISTING_GROUP_ID" 2>/dev/null
    # Delete the group
    magento_query_headers "DELETE FROM customer_group WHERE customer_group_id=$EXISTING_GROUP_ID" 2>/dev/null
fi

# 2. Ensure the target customer exists
TARGET_EMAIL="john.smith@example.com"
CUSTOMER_DATA=$(get_customer_by_email "$TARGET_EMAIL" 2>/dev/null)

if [ -z "$CUSTOMER_DATA" ]; then
    echo "Creating missing customer: $TARGET_EMAIL..."
    # Use Magento CLI to create customer if missing
    docker exec magento-web php bin/magento customer:create \
        --firstname="John" --lastname="Smith" \
        --email="$TARGET_EMAIL" --password="Password123" 2>/dev/null || true
else
    # Reset John Smith to General group (ID 1) just in case
    echo "Resetting John Smith to General group..."
    magento_query_headers "UPDATE customer_entity SET group_id=1 WHERE email='$TARGET_EMAIL'" 2>/dev/null
fi

# 3. Record initial state counters
echo "Recording initial state..."
INITIAL_GROUP_COUNT=$(magento_query "SELECT COUNT(*) FROM customer_group" 2>/dev/null | tail -1 | tr -d '[:space:]')
# Count existing tier prices for our target items (should be 0 for this new group, but counting global)
INITIAL_TIER_PRICE_COUNT=$(magento_query "SELECT COUNT(*) FROM catalog_product_entity_tier_price" 2>/dev/null | tail -1 | tr -d '[:space:]')

echo "${INITIAL_GROUP_COUNT:-0}" > /tmp/initial_group_count
echo "${INITIAL_TIER_PRICE_COUNT:-0}" > /tmp/initial_tier_price_count

# 4. Ensure Firefox is running and logged in
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Auto-login if needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Attempting login..."
    sleep 2
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_USER"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "$ADMIN_PASS"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 10
fi

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="