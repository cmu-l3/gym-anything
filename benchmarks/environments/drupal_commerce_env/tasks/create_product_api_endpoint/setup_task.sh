#!/bin/bash
# Setup script for Create Product API Endpoint task

echo "=== Setting up Create Product API Endpoint Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure services are running
ensure_services_running 120

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure 'rest' and 'serialization' modules are DISABLED initially
# This ensures the agent has to enable them
echo "Ensuring REST modules are disabled..."
cd /var/www/html/drupal
$DRUSH pm:uninstall -y rest serialization basic_auth 2>/dev/null || true

# Ensure enough products exist for the limit requirement
echo "Checking product count..."
PRODUCT_COUNT=$(get_product_count)
if [ "$PRODUCT_COUNT" -lt 10 ]; then
    echo "Seeding additional products..."
    # Quick PHP script to generate dummy products if needed
    $DRUSH php:eval '
    use Drupal\commerce_product\Entity\Product;
    use Drupal\commerce_product\Entity\ProductVariation;
    use Drupal\commerce_price\Price;
    
    $store = \Drupal\commerce_store\Entity\Store::load(1);
    for ($i = 0; $i < 5; $i++) {
        $variation = ProductVariation::create([
            "type" => "default",
            "sku" => "API-TEST-" . $i,
            "price" => new Price("19.99", "USD"),
            "status" => 1,
        ]);
        $variation->save();
        
        $product = Product::create([
            "uid" => 1,
            "type" => "default",
            "title" => "API Test Product " . $i,
            "stores" => [$store],
            "variations" => [$variation],
            "status" => 1,
        ]);
        $product->save();
    }
    ' 2>/dev/null
    echo "Added spacer products."
fi

# Ensure Drupal admin page is showing
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page"
fi

# Navigate to the Extend page (Modules) to give a hint/start point
echo "Navigating to Modules page..."
navigate_firefox_to "http://localhost/admin/modules"
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