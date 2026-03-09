#!/bin/bash
# Setup script for edit_and_place_order task
echo "=== Setting up edit_and_place_order ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure services are running
ensure_services_running 120

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the specific draft order for this task using Drush PHP
# We create a draft order for uid=2 (johndoe) with 1x Sony Headphones
echo "Creating draft order..."
cat > /tmp/create_draft_order.php << 'PHPEOF'
use Drupal\commerce_order\Entity\Order;
use Drupal\commerce_order\Entity\OrderItem;
use Drupal\commerce_price\Price;
use Drupal\profile\Entity\Profile;
use Drupal\commerce_product\Entity\ProductVariation;

// 1. Load the variation for Sony Headphones (SKU: SONY-WH1000XM5)
// In the seed data, this is usually variation_id 1, but let's look it up to be safe
$ids = \Drupal::entityQuery('commerce_product_variation')
  ->condition('sku', 'SONY-WH1000XM5')
  ->accessCheck(FALSE)
  ->execute();
$variation_id = reset($ids);

if (!$variation_id) {
    echo "ERROR: Sony variation not found";
    exit(1);
}
$variation = ProductVariation::load($variation_id);

// 2. Create Order Item
$order_item = OrderItem::create([
  'type' => 'default',
  'purchased_entity' => $variation,
  'quantity' => 1,
  'unit_price' => $variation->getPrice(),
  'title' => $variation->getTitle(),
]);
$order_item->save();

// 3. Create Billing Profile (Old address to be updated)
$profile = Profile::create([
  'type' => 'customer',
  'uid' => 2,
  'address' => [
    'country_code' => 'US',
    'address_line1' => '100 Temp Street',
    'locality' => 'Portland',
    'administrative_area' => 'OR',
    'postal_code' => '97201',
    'given_name' => 'John',
    'family_name' => 'Doe',
  ],
]);
$profile->save();

// 4. Create Order
$order = Order::create([
  'type' => 'default',
  'store_id' => 1,
  'uid' => 2, // johndoe
  'state' => 'draft',
  'billing_profile' => $profile,
  'order_items' => [$order_item],
  'mail' => 'john.doe@example.com',
]);
$order->save();

echo "ORDER_ID:" . $order->id();
PHPEOF

# Execute the PHP script via Drush
OUTPUT=$(cd /var/www/html/drupal && vendor/bin/drush php:script /tmp/create_draft_order.php 2>&1)

# Extract Order ID
ORDER_ID=$(echo "$OUTPUT" | grep "ORDER_ID:" | cut -d':' -f2 | tr -d '[:space:]')

if [ -z "$ORDER_ID" ]; then
    echo "ERROR: Failed to create draft order. Output: $OUTPUT"
    exit 1
fi

echo "Created draft order ID: $ORDER_ID"
echo "$ORDER_ID" > /tmp/target_order_id.txt

# Verify the order exists in DB and record initial state
ORDER_CHECK=$(drupal_db_query "SELECT state FROM commerce_order WHERE order_id = $ORDER_ID")
echo "Initial Order State: $ORDER_CHECK"

# Ensure Drupal admin page is shown
navigate_firefox_to "http://localhost/admin/commerce/orders"
ensure_drupal_shown 60

# Maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="