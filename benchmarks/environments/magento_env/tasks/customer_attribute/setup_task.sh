#!/bin/bash
# Setup script for Customer Attribute task

echo "=== Setting up Customer Attribute Task ==="

source /workspace/scripts/task_utils.sh

# Record initial customer attribute count
echo "Recording initial customer attribute count..."
CUSTOMER_ENTITY_TYPE_ID=$(magento_query "SELECT entity_type_id FROM eav_entity_type WHERE entity_type_code='customer' LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "1")
INITIAL_ATTR_COUNT=$(magento_query "SELECT COUNT(*) FROM eav_attribute WHERE entity_type_id=$CUSTOMER_ENTITY_TYPE_ID AND is_user_defined=1" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "${CUSTOMER_ENTITY_TYPE_ID:-1}" > /tmp/customer_entity_type_id
echo "${INITIAL_ATTR_COUNT:-0}" > /tmp/initial_customer_attr_count
echo "Customer entity_type_id: $CUSTOMER_ENTITY_TYPE_ID, initial user-defined attrs: $INITIAL_ATTR_COUNT"

# Check if skin_concern already exists (for idempotency check)
EXISTING_SKIN=$(magento_query "SELECT COUNT(*) FROM eav_attribute WHERE attribute_code='skin_concern' AND entity_type_id=$CUSTOMER_ENTITY_TYPE_ID" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
echo "${EXISTING_SKIN:-0}" > /tmp/skin_concern_exists_at_start
echo "skin_concern already exists: ${EXISTING_SKIN:-0}"

# Ensure Firefox is running and logged in
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/admin' > /tmp/firefox_task.log 2>&1 &"
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

WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Attempting login..."
    sleep 2
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "Admin1234!"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 10
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Customer Attribute Task Setup Complete ==="
echo ""
echo "Navigate to: Stores > Attributes > Customer"
echo "Magento Admin: http://localhost/admin  |  admin / Admin1234!"
echo ""
