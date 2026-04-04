#!/bin/bash
# Setup script for setup_clearance_section task

echo "=== Setting up setup_clearance_section ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure services are running
ensure_services_running 120

# Record initial field existence (should be 0)
# Check if the field config already exists (it shouldn't)
INITIAL_FIELD_CHECK=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.storage.commerce_product.field_clearance'" 2>/dev/null || echo "0")
echo "$INITIAL_FIELD_CHECK" > /tmp/initial_field_check.txt

# Verify target products exist so the agent can actually flag them
SONY_CHECK=$(product_exists_by_title "Sony WH-1000XM5 Wireless Headphones")
LOGI_CHECK=$(product_exists_by_title "Logitech MX Master 3S")

if [ "$SONY_CHECK" != "true" ] || [ "$LOGI_CHECK" != "true" ]; then
    echo "WARNING: Target products not found. Re-seeding might be required."
    # We could trigger a re-seed here if strictly necessary, but assuming env is good.
fi

# Ensure Drupal admin is reachable
if ! ensure_drupal_shown 60; then
    echo "WARNING: Drupal admin not detected."
fi

# Contextual start: Navigate to Product Types configuration
# This gives the agent a hint/head start on where to add the field
echo "Navigating to Product Types configuration..."
navigate_firefox_to "http://localhost/admin/commerce/config/product-types/default/edit/fields"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="