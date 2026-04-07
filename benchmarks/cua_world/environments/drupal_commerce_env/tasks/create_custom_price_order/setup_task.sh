#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: create_custom_price_order ==="

# 1. Ensure clean state (no orders for mikewilson ideally, or we count them)
INITIAL_ORDER_COUNT=$(get_order_count)
echo "$INITIAL_ORDER_COUNT" > /tmp/initial_order_count.txt

# 2. Verify products exist
if ! product_exists_by_title "Samsung Galaxy Buds2 Pro"; then
    echo "Creating missing product: Samsung Galaxy Buds2 Pro"
    # Fallback creation if seed failed
    drush_cmd php:eval '
      use Drupal\commerce_product\Entity\Product;
      use Drupal\commerce_product\Entity\ProductVariation;
      $variation = ProductVariation::create(["type" => "default", "sku" => "SAMSUNG-BUDS2", "price" => ["number" => "229.99", "currency_code" => "USD"], "title" => "Samsung Galaxy Buds2 Pro"]);
      $variation->save();
      $product = Product::create(["type" => "default", "title" => "Samsung Galaxy Buds2 Pro", "variations" => [$variation], "stores" => [1]]);
      $product->save();
    '
fi

if ! product_exists_by_title "Logitech MX Master 3S"; then
    echo "Creating missing product: Logitech MX Master 3S"
    drush_cmd php:eval '
      use Drupal\commerce_product\Entity\Product;
      use Drupal\commerce_product\Entity\ProductVariation;
      $variation = ProductVariation::create(["type" => "default", "sku" => "LOGI-MXM3S", "price" => ["number" => "99.99", "currency_code" => "USD"], "title" => "Logitech MX Master 3S"]);
      $variation->save();
      $product = Product::create(["type" => "default", "title" => "Logitech MX Master 3S", "variations" => [$variation], "stores" => [1]]);
      $product->save();
    '
fi

# 3. Verify customer exists
if ! user_exists "mikewilson"; then
    echo "Creating user mikewilson..."
    drush_cmd user:create mikewilson --mail="mike.wilson@example.com" --password="Customer123!"
fi

# 4. Launch Firefox and login
ensure_drupal_shown

# Navigate to Orders page to start
navigate_firefox_to "http://localhost/admin/commerce/orders"

echo "=== Task setup complete ==="