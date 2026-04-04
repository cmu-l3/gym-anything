#!/bin/bash
set -e
echo "=== Setting up task: split_backordered_order ==="

# Load helper functions
source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure 'Manual' Payment Gateway exists (needed to 'Place' orders manually)
echo "Ensuring Manual Payment Gateway exists..."
cd /var/www/html/drupal
$DRUSH php:eval '
use Drupal\commerce_payment\Entity\PaymentGateway;
if (!PaymentGateway::load("manual")) {
  $gateway = PaymentGateway::create([
    "id" => "manual",
    "label" => "Manual Payment",
    "plugin" => "manual",
    "status" => TRUE,
  ]);
  $gateway->save();
  echo "Created Manual Payment Gateway.\n";
} else {
  echo "Manual Payment Gateway already exists.\n";
}
'

# 2. Get Product Variation IDs
echo "Fetching variation IDs..."
SONY_ID=$(get_variation_by_sku "SONY-WH1000XM5")
LOGI_ID=$(get_variation_by_sku "LOGI-MXM3S")
DELL_ID=$(get_variation_by_sku "DELL-XPS13-16-512") # Default Dell SKU from seed

# If Dell doesn't exist (seed variation might be different), find any Dell or create a placeholder
if [ -z "$DELL_ID" ]; then
    DELL_ID=$(drupal_db_query "SELECT variation_id FROM commerce_product_variation_field_data WHERE title LIKE '%Dell%' LIMIT 1")
fi

if [ -z "$SONY_ID" ] || [ -z "$LOGI_ID" ] || [ -z "$DELL_ID" ]; then
    echo "ERROR: Could not find required products. Re-running seed..."
    $DRUSH php:script /tmp/seed_products.php
    SONY_ID=$(get_variation_by_sku "SONY-WH1000XM5")
    LOGI_ID=$(get_variation_by_sku "LOGI-MXM3S")
    DELL_ID=$(get_variation_by_sku "DELL-XPS13-16-512")
fi

# 3. Create the Draft Order for janesmith
echo "Creating initial draft order..."
ORDER_ID=$($DRUSH php:eval "
use Drupal\commerce_product\Entity\ProductVariation;
use Drupal\commerce_order\Entity\Order;
use Drupal\commerce_price\Price;
use Drupal\commerce_order\Entity\OrderItem;

\$user = user_load_by_name('janesmith');
if (!\$user) { die('User janesmith not found'); }

// Create Order Items
\$item1 = OrderItem::create(['type' => 'default', 'purchased_entity' => $SONY_ID, 'quantity' => 1, 'unit_price' => new Price('348.00', 'USD')]);
\$item1->save();
\$item2 = OrderItem::create(['type' => 'default', 'purchased_entity' => $LOGI_ID, 'quantity' => 1, 'unit_price' => new Price('99.99', 'USD')]);
\$item2->save();
\$item3 = OrderItem::create(['type' => 'default', 'purchased_entity' => $DELL_ID, 'quantity' => 1, 'unit_price' => new Price('1249.99', 'USD')]);
\$item3->save();

// Create Order
\$order = Order::create([
  'type' => 'default',
  'state' => 'draft',
  'uid' => \$user->id(),
  'store_id' => 1,
  'order_items' => [\$item1, \$item2, \$item3],
]);
\$order->save();
echo \$order->id();
")

echo "Created Order ID: $ORDER_ID"
echo "$ORDER_ID" > /tmp/original_order_id.txt

# 4. Prepare UI
ensure_drupal_shown
navigate_firefox_to "http://localhost/admin/commerce/orders"

echo "=== Task setup complete ==="