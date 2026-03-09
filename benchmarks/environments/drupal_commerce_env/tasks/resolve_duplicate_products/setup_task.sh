#!/bin/bash
# Setup script for resolve_duplicate_products task

echo "=== Setting up Resolve Duplicate Products Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure services are running and Drupal is ready
ensure_services_running 120

# 2. Reset catalog to known clean state (run seed script)
echo "Resetting catalog to clean state..."
if [ -f /workspace/scripts/seed_products.php ]; then
    drush_cmd php:script /workspace/scripts/seed_products.php
else
    # Fallback if specific seed script location varies, though env spec says it's there
    # Assuming the environment startup already seeded basic data, we just proceed
    echo "Seed script not found, assuming catalog is populated."
fi

# 3. Create the "Botched Import" Scenario using Drush PHP
# - Create duplicates for 4 specific products
# - Corrupt price of Bose QCU
echo "Generating duplicates and corrupting data..."

drush_cmd php:eval '
use Drupal\commerce_product\Entity\Product;
use Drupal\commerce_product\Entity\ProductVariation;

// 1. Corrupt Bose Price
$bose_sku = "BOSE-QCU";
$variations = \Drupal::entityTypeManager()->getStorage("commerce_product_variation")->loadByProperties(["sku" => $bose_sku]);
if ($variations) {
  $variation = reset($variations);
  $variation->setPrice(new \Drupal\commerce_price\Price("329.00", "USD"));
  $variation->save();
  echo "Corrupted price for $bose_sku to $329.00\n";
} else {
  echo "ERROR: Base product $bose_sku not found!\n";
}

// 2. Create Duplicates
$targets = [
  "SONY-WH1000XM5" => "IMPORT-SONY-WH1000XM5",
  "APPLE-MBP16" => "IMPORT-APPLE-MBP16",
  "LOGI-MXM3S" => "IMPORT-LOGI-MXM3S",
  "DELL-XPS15" => "IMPORT-DELL-XPS15"
];

foreach ($targets as $original_sku => $new_sku) {
  $vars = \Drupal::entityTypeManager()->getStorage("commerce_product_variation")->loadByProperties(["sku" => $original_sku]);
  if ($vars) {
    $original_var = reset($vars);
    $original_product = $original_var->getProduct();
    
    // Create new variation
    $new_var = $original_var->createDuplicate();
    $new_var->setSku($new_sku);
    $new_var->save();
    
    // Create new product wrapper for this variation (since Drupal Commerce uses Product -> Variation model)
    $new_product = $original_product->createDuplicate();
    $new_product->setVariations([$new_var]);
    $new_product->save();
    
    echo "Created duplicate: " . $new_product->getTitle() . " ($new_sku)\n";
  }
}
'

# 4. Record Initial State for Anti-Gaming
echo "Recording initial state..."
INITIAL_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product_field_data WHERE status=1")
echo "$INITIAL_COUNT" > /tmp/initial_product_count
echo "Initial product count: $INITIAL_COUNT"

# Record IDs of the specific duplicates to ensure THESE specifically are deleted
drupal_db_query "SELECT variation_id FROM commerce_product_variation_field_data WHERE sku LIKE 'IMPORT-%'" > /tmp/duplicate_variation_ids.txt

# Timestamp
date +%s > /tmp/task_start_time.txt

# 5. Prepare User Interface
echo "Navigating to Products page..."
ensure_drupal_shown 60
navigate_firefox_to "http://localhost/admin/commerce/products"
sleep 5

# Focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
fi

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="