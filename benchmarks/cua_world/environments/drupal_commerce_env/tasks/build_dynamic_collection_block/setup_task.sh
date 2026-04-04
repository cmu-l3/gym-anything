#!/bin/bash
# Setup script for build_dynamic_collection_block
echo "=== Setting up Build Dynamic Collection Block Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# Ensure services are running
ensure_services_running 120

# Ensure Drupal admin page is accessible
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Clean up any previous attempts (idempotency)
echo "Cleaning up any previous task artifacts..."

# 1. Delete block placement
$DRUSH config:delete block.block.olivero_summer_collection -y 2>/dev/null || true
$DRUSH config:delete block.block.views_block__summer_collection_block_1 -y 2>/dev/null || true

# 2. Delete view
$DRUSH config:delete views.view.summer_collection -y 2>/dev/null || true

# 3. Remove field data and configuration
# This is destructive/complex in Drupal, so we try to delete the field config
$DRUSH field:delete commerce_product.default.field_collection -y 2>/dev/null || true
$DRUSH field:delete commerce_product.field_collection -y 2>/dev/null || true

# 4. Delete vocabulary
$DRUSH entity:delete taxonomy_vocabulary collections -y 2>/dev/null || true

# Clear cache to ensure clean state
$DRUSH cr 2>/dev/null || true

# Verify target products exist
echo "Verifying target products..."
SONY_EXISTS=$(product_exists_by_title "Sony WH-1000XM5 Wireless Headphones" && echo "true" || echo "false")
LOGI_EXISTS=$(product_exists_by_title "Logitech MX Master 3S Wireless Mouse" && echo "true" || echo "false")

if [ "$SONY_EXISTS" = "false" ] || [ "$LOGI_EXISTS" = "false" ]; then
    echo "ERROR: Target products missing from environment!"
    # In a real scenario, we might re-seed them here
    exit 1
fi

# Navigate to Structure page to start
navigate_firefox_to "http://localhost/admin/structure"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="