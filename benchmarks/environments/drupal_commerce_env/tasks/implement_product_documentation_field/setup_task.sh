#!/bin/bash
# Setup script for implement_product_documentation_field task
echo "=== Setting up implement_product_documentation_field ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Fallback definitions if task_utils missing
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# 1. Ensure services are running
ensure_services_running 120

# 2. Cleanup: Remove the field if it already exists (from a previous run)
echo "Checking for existing field_user_manual..."
FIELD_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.storage.commerce_product.field_user_manual'")

if [ "$FIELD_EXISTS" -gt 0 ]; then
    echo "Field exists, cleaning up..."
    # We use Drush to delete the field properly to clean up DB tables
    cd /var/www/html/drupal
    vendor/bin/drush field:delete commerce_product field_user_manual -y >/dev/null 2>&1 || true
    vendor/bin/drush cr >/dev/null 2>&1
fi

# 3. Ensure the target product exists
TARGET_SKU="SONY-WH1000XM5"
PRODUCT_EXISTS=$(get_variation_by_sku "$TARGET_SKU")

if [ -z "$PRODUCT_EXISTS" ]; then
    echo "Target product SONY-WH1000XM5 missing. Re-seeding data..."
    # Re-run seed script if needed, or manually create
    cd /var/www/html/drupal
    vendor/bin/drush php:eval "
      \$variation = \Drupal\commerce_product\Entity\ProductVariation::create([
        'type' => 'default',
        'sku' => '$TARGET_SKU',
        'price' => new \Drupal\commerce_price\Price('348.00', 'USD'),
        'status' => 1,
      ]);
      \$variation->save();
      \$product = \Drupal\commerce_product\Entity\Product::create([
        'type' => 'default',
        'title' => 'Sony WH-1000XM5 Wireless Headphones',
        'variations' => [\$variation],
        'stores' => [1], 
        'status' => 1,
      ]);
      \$product->save();
    "
fi

# 4. Record timestamp
date +%s > /tmp/task_start_timestamp

# 5. Navigate Firefox to the Product Types configuration page to start
navigate_firefox_to "http://localhost/admin/commerce/config/product-types"
sleep 5

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="