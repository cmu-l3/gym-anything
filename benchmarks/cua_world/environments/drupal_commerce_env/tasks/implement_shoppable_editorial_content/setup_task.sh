#!/bin/bash
# Setup script for implement_shoppable_editorial_content
echo "=== Setting up Shoppable Content Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# Ensure services are running
ensure_services_running 120

# Clean up previous attempts (if any) to ensure a clean start
echo "Cleaning up any existing 'editorial_review' configuration..."
# Delete nodes of this type
drupal_db_query "DELETE FROM node_field_data WHERE type='editorial_review'" 2>/dev/null || true
drupal_db_query "DELETE FROM node__field_merchandise" 2>/dev/null || true
# Delete the field config
drupal_db_query "DELETE FROM config WHERE name LIKE '%field.field.node.editorial_review.field_merchandise%'" 2>/dev/null || true
drupal_db_query "DELETE FROM config WHERE name LIKE '%field.storage.node.field_merchandise%'" 2>/dev/null || true
# Delete the content type config
drupal_db_query "DELETE FROM config WHERE name='node.type.editorial_review'" 2>/dev/null || true
# Clear cache to apply deletions (using Drush if available, otherwise just rely on DB state for now)
cd /var/www/html/drupal && vendor/bin/drush cr > /dev/null 2>&1 || true

# Verify the product to be referenced exists
SONY_CHECK=$(drupal_db_query "SELECT product_id FROM commerce_product_field_data WHERE title LIKE '%Sony WH-1000XM5%' LIMIT 1")
if [ -z "$SONY_CHECK" ]; then
    echo "WARNING: Sony product not found. Seeding it..."
    # Fallback creation if seed failed
    cd /var/www/html/drupal && vendor/bin/drush php:eval '
      $product = \Drupal\commerce_product\Entity\Product::create([
        "type" => "default",
        "title" => "Sony WH-1000XM5 Wireless Headphones",
        "stores" => [1],
      ]);
      $product->save();
    '
fi

# Ensure Drupal admin is reachable
echo "Ensuring Drupal admin page is displayed..."
navigate_firefox_to "http://localhost/admin/structure/types"
sleep 5

# Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="