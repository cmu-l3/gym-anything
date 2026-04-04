#!/bin/bash
# Setup script for Add Product Variations task
# Ensures the parent product "Dell XPS 13 Laptop" exists and navigates to product list

echo "=== Setting up Add Product Variations Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Ensure services are running
ensure_services_running 90

# 1. Ensure the parent product "Dell XPS 13 Laptop" exists
# We use drush php:eval to check/create it to guarantee consistent starting state
echo "Ensuring parent product exists..."
cd /var/www/html/drupal

$DRUSH php:eval '
use Drupal\commerce_product\Entity\Product;
use Drupal\commerce_product\Entity\ProductVariation;
use Drupal\commerce_price\Price;

// Check if product exists
$ids = \Drupal::entityQuery("commerce_product")
  ->condition("title", "Dell XPS 13 Laptop")
  ->accessCheck(FALSE)
  ->execute();

if (empty($ids)) {
  echo "Creating Dell XPS 13 Laptop product...\n";
  
  // Create base variation
  $variation = ProductVariation::create([
    "type" => "default",
    "sku" => "DELL-XPS13-BASE",
    "price" => new Price("999.99", "USD"),
    "title" => "Dell XPS 13 - 8GB/256GB",
    "status" => 1,
  ]);
  $variation->save();

  // Create product
  $product = Product::create([
    "uid" => 1,
    "type" => "default",
    "title" => "Dell XPS 13 Laptop",
    "stores" => [1], // Assuming store ID 1 exists from install script
    "variations" => [$variation],
    "status" => 1,
  ]);
  $product->save();
  echo "Product created with ID: " . $product->id() . "\n";
} else {
  echo "Dell XPS 13 Laptop already exists (ID: " . reset($ids) . ")\n";
  
  // Clean up any previous attempts at the target variations (idempotency)
  $target_skus = ["DELL-XPS13-16-512", "DELL-XPS13-32-1TB"];
  $v_ids = \Drupal::entityQuery("commerce_product_variation")
    ->condition("sku", $target_skus, "IN")
    ->accessCheck(FALSE)
    ->execute();
    
  if (!empty($v_ids)) {
    $storage = \Drupal::entityTypeManager()->getStorage("commerce_product_variation");
    $vars = $storage->loadMultiple($v_ids);
    $storage->delete($vars);
    echo "Cleaned up " . count($v_ids) . " existing target variations.\n";
  }
}
'

# 2. Record initial variation count for this product
# We need the product ID first
PRODUCT_ID=$(get_product_id_by_title "Dell XPS 13 Laptop")
echo "Target Product ID: $PRODUCT_ID"

if [ -n "$PRODUCT_ID" ]; then
    # Count variations linked to this product
    INITIAL_VAR_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product__variations WHERE entity_id = $PRODUCT_ID")
else
    INITIAL_VAR_COUNT=0
fi

echo "$INITIAL_VAR_COUNT" > /tmp/initial_variation_count
echo "$PRODUCT_ID" > /tmp/target_product_id
echo "Initial variation count: $INITIAL_VAR_COUNT"

# 3. Navigate Firefox to the product list
echo "Navigating to Commerce > Products..."
ensure_drupal_shown 60
navigate_firefox_to "http://localhost/admin/commerce/products"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Add Product Variations Setup Complete ==="