#!/bin/bash
# Setup script for Setup Apparel Product Type task
echo "=== Setting up Setup Apparel Product Type Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure services are running (Apache, MariaDB, etc.)
ensure_services_running 90

# 2. Record start time for anti-gaming (timestamps on created entities)
date +%s > /tmp/task_start_timestamp

# 3. Clean up any previous attempts (idempotency)
# We delete specific config/content if it exists to ensure a clean slate
echo "Cleaning up potential stale data..."
cd /var/www/html/drupal
# Delete product if exists
$DRUSH entity:delete commerce_product --bundle=apparel 2>/dev/null || true
# Delete product type if exists
$DRUSH config:delete commerce_product.commerce_product_type.apparel 2>/dev/null || true
# Delete variation type if exists
$DRUSH config:delete commerce_product.commerce_product_variation_type.apparel 2>/dev/null || true
# Delete attributes if exist
$DRUSH entity:delete commerce_product_attribute --bundle=color 2>/dev/null || true
$DRUSH entity:delete commerce_product_attribute --bundle=size 2>/dev/null || true
$DRUSH config:delete commerce_product.commerce_product_attribute.color 2>/dev/null || true
$DRUSH config:delete commerce_product.commerce_product_attribute.size 2>/dev/null || true
# Clear cache to apply deletions
$DRUSH cr > /dev/null 2>&1

# 4. Navigate Firefox to the initial admin page
echo "Navigating Firefox to Commerce Overview..."
ensure_drupal_shown 60
navigate_firefox_to "http://localhost/admin/commerce"

# 5. Maximize window for best VLM visibility
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="