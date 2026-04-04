#!/bin/bash
# Setup script for Tax Configuration task

echo "=== Setting up Tax Configuration Task ==="

source /workspace/scripts/task_utils.sh

# Record initial tax entity counts
echo "Recording initial tax entity counts..."
INITIAL_TAX_CLASS_COUNT=$(magento_query "SELECT COUNT(*) FROM tax_class WHERE class_type='PRODUCT'" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_TAX_RATE_COUNT=$(magento_query "SELECT COUNT(*) FROM tax_calculation_rate" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_TAX_RULE_COUNT=$(magento_query "SELECT COUNT(*) FROM tax_calculation_rule" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "${INITIAL_TAX_CLASS_COUNT:-0}" > /tmp/initial_tax_class_count
echo "${INITIAL_TAX_RATE_COUNT:-0}" > /tmp/initial_tax_rate_count
echo "${INITIAL_TAX_RULE_COUNT:-0}" > /tmp/initial_tax_rule_count
echo "Initial counts: product_tax_classes=$INITIAL_TAX_CLASS_COUNT rates=$INITIAL_TAX_RATE_COUNT rules=$INITIAL_TAX_RULE_COUNT"

# Record California and New York region IDs for reference
CA_REGION_ID=$(magento_query "SELECT region_id FROM directory_country_region WHERE country_id='US' AND code='CA' LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
NY_REGION_ID=$(magento_query "SELECT region_id FROM directory_country_region WHERE country_id='US' AND code='NY' LIMIT 1" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
echo "${CA_REGION_ID:-0}" > /tmp/ca_region_id
echo "${NY_REGION_ID:-0}" > /tmp/ny_region_id
echo "CA region_id=$CA_REGION_ID NY region_id=$NY_REGION_ID"

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

echo "=== Tax Configuration Task Setup Complete ==="
echo ""
echo "Navigate to: Stores > Taxes"
echo "Magento Admin: http://localhost/admin  |  admin / Admin1234!"
echo ""
