#!/bin/bash
# Setup script for consolidate_customer_accounts task
echo "=== Setting up consolidate_customer_accounts ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure services are running
ensure_services_running 120

# 1. Create the two users
echo "Creating customer accounts..."
# Create sarah.old if not exists
if ! user_exists "sarah.old"; then
    cd /var/www/html/drupal && vendor/bin/drush user:create sarah.old --mail="sarah.old@example.com" --password="password"
fi
# Create sarah.jenkins if not exists
if ! user_exists "sarah.jenkins"; then
    cd /var/www/html/drupal && vendor/bin/drush user:create sarah.jenkins --mail="sarah.jenkins@example.com" --password="password"
fi

# Get their UIDs
UID_OLD=$(drupal_db_query "SELECT uid FROM users_field_data WHERE name='sarah.old'")
UID_NEW=$(drupal_db_query "SELECT uid FROM users_field_data WHERE name='sarah.jenkins'")

echo "sarah.old UID: $UID_OLD"
echo "sarah.jenkins UID: $UID_NEW"

# Save UIDs for export/verification later
echo "$UID_OLD" > /tmp/uid_old.txt
echo "$UID_NEW" > /tmp/uid_new.txt

# 2. Create an order assigned to sarah.old
echo "Creating order for sarah.old..."
# We use drush php:eval to create a proper order entity with an item
cd /var/www/html/drupal && vendor/bin/drush php:eval "
use Drupal\commerce_order\Entity\Order;
use Drupal\commerce_price\Price;
use Drupal\commerce_product\Entity\ProductVariation;
use Drupal\commerce_order\Entity\OrderItem;

// Load a variation (assuming standard install has some, e.g. ID 1)
\$variation = ProductVariation::load(1);
if (!\$variation) {
  die('No variation found');
}

// Create order item
\$order_item = OrderItem::create([
  'type' => 'default',
  'purchased_entity' => \$variation,
  'quantity' => 1,
  'unit_price' => \$variation->getPrice(),
]);
\$order_item->save();

// Create order
\$order = Order::create([
  'type' => 'default',
  'state' => 'draft',
  'mail' => 'sarah.old@example.com',
  'uid' => $UID_OLD,
  'store_id' => 1,
  'order_number' => '1',
  'order_items' => [\$order_item],
]);
\$order->save();
echo 'Created Order ' . \$order->id();
"

# Verify order exists
ORDER_ID=$(drupal_db_query "SELECT order_id FROM commerce_order WHERE order_number='1'")
echo "Created Order ID: $ORDER_ID assigned to UID $UID_OLD"
echo "$ORDER_ID" > /tmp/target_order_id.txt

# 3. Prepare the browser
echo "Navigating Firefox to Orders page..."
ensure_drupal_shown 60
navigate_firefox_to "http://localhost/admin/commerce/orders"

# Take screenshot
take_screenshot /tmp/task_start_screenshot.png

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup Complete ==="