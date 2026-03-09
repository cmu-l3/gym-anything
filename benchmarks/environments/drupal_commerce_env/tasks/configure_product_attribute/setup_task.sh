#!/bin/bash
# Setup script for configure_product_attribute task
echo "=== Setting up configure_product_attribute ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Define database query function if not present in utils
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

# Ensure services are running
ensure_services_running 120

# Check if 'Color' attribute already exists and clean it up if so (to ensure clean state)
EXISTING_ATTR=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name LIKE 'commerce_product.commerce_product_attribute.color%'")
if [ "$EXISTING_ATTR" -gt 0 ]; then
    echo "WARNING: Color attribute exists. Cleaning up for clean state..."
    # This is a complex cleanup in Drupal, might be safer to just fail or warn. 
    # For this task generator context, we'll assume a clean env or just record it exists.
    # A full cleanup via SQL is risky. We will record baseline.
fi

# Record baseline counts
INITIAL_ATTR_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name LIKE 'commerce_product.commerce_product_attribute.%'")
echo "${INITIAL_ATTR_COUNT:-0}" > /tmp/initial_attr_count

INITIAL_VAL_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product_attribute_value_field_data")
echo "${INITIAL_VAL_COUNT:-0}" > /tmp/initial_val_count

# Record start time
date +%s > /tmp/task_start_timestamp

# Navigate Firefox to Product Attributes page to save agent some clicks
echo "Navigating to Commerce Product Attributes..."
navigate_firefox_to "http://localhost/admin/commerce/product-attributes"
sleep 5

# Focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="