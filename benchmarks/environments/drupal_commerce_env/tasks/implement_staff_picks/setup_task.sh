#!/bin/bash
# Setup script for Implement Staff Picks task
echo "=== Setting up Implement Staff Picks Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure Services Running
echo "Verifying infrastructure services..."
ensure_services_running 90

# 2. Record Target Product IDs
# We need to know which IDs correspond to the products the agent must tag
echo "Identifying target products..."

SONY_ID=$(get_product_id_by_title "Sony WH-1000XM5 Wireless Headphones" 2>/dev/null)
LOGI_ID=$(get_product_id_by_title "Logitech MX Master 3S Wireless Mouse" 2>/dev/null)

if [ -z "$SONY_ID" ] || [ -z "$LOGI_ID" ]; then
    echo "ERROR: Target products not found in database. Seeding data..."
    # Fallback: Run seed script if products missing
    $DRUSH php:script /tmp/seed_products.php > /dev/null 2>&1
    SONY_ID=$(get_product_id_by_title "Sony WH-1000XM5 Wireless Headphones" 2>/dev/null)
    LOGI_ID=$(get_product_id_by_title "Logitech MX Master 3S Wireless Mouse" 2>/dev/null)
fi

echo "Target IDs: Sony=$SONY_ID, Logitech=$LOGI_ID"
echo "{\"sony_id\": \"$SONY_ID\", \"logitech_id\": \"$LOGI_ID\"}" > /tmp/target_ids.json
chmod 666 /tmp/target_ids.json

# 3. Clean Slate (Optional but good practice)
# Remove field if it already exists from a previous run
if drupal_db_query "DESCRIBE commerce_product__field_staff_pick" >/dev/null 2>&1; then
    echo "Cleaning up previous 'field_staff_pick'..."
    $DRUSH field:delete commerce_product.default.field_staff_pick -y >/dev/null 2>&1 || true
    $DRUSH cr >/dev/null 2>&1
fi

# 4. Navigate to Admin Dashboard
echo "Navigating to Commerce Dashboard..."
navigate_firefox_to "http://localhost/admin/commerce"
sleep 5

# 5. Capture Initial State
date +%s > /tmp/task_start_timestamp
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="