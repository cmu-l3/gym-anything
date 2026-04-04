#!/bin/bash
echo "=== Setting up Process Pending Orders Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
ensure_services_running 120

# Create the specific draft orders using a PHP script via Drush
# We generate a PHP script that creates the orders and outputs their IDs to a JSON file
cat > /tmp/create_task_orders.php << 'PHPEOF'
use Drupal\commerce_order\Entity\Order;
use Drupal\commerce_order\Entity\OrderItem;
use Drupal\commerce_product\Entity\ProductVariation;
use Drupal\commerce_price\Price;
use Drupal\user\Entity\User;

// Helper to get user by name
function get_uid($name) {
  $users = \Drupal::entityTypeManager()->getStorage('user')->loadByProperties(['name' => $name]);
  $user = reset($users);
  return $user ? $user->id() : 0;
}

// Helper to get variation by SKU
function get_variation($sku) {
  $vars = \Drupal::entityTypeManager()->getStorage('commerce_product_variation')->loadByProperties(['sku' => $sku]);
  return reset($vars);
}

// Helper to create order
function create_order($uid, $sku, $qty = 1) {
  $variation = get_variation($sku);
  if (!$variation) return null;
  
  $order_item = OrderItem::create([
    'type' => 'default',
    'purchased_entity' => $variation,
    'quantity' => $qty,
    'unit_price' => $variation->getPrice(),
    'title' => $variation->getTitle(),
  ]);
  $order_item->save();

  $order = Order::create([
    'type' => 'default',
    'state' => 'draft',
    'mail' => $uid ? User::load($uid)->getEmail() : 'guest@example.com',
    'uid' => $uid,
    'store_id' => 1,
    'order_items' => [$order_item],
    'placed' => time(),
  ]);
  $order->save();
  return $order->id();
}

$orders = [];

// Order 1: Johndoe / Sony
$id1 = create_order(get_uid('johndoe'), 'SONY-WH1000XM5');
$orders[] = ['id' => $id1, 'customer' => 'johndoe', 'sku' => 'SONY-WH1000XM5'];

// Order 2: Janesmith / Logitech (make this one created slightly later)
sleep(1);
$id2 = create_order(get_uid('janesmith'), 'LOGI-MXM3S');
$orders[] = ['id' => $id2, 'customer' => 'janesmith', 'sku' => 'LOGI-MXM3S'];

// Order 3: Mikewilson / Samsung
sleep(1);
$id3 = create_order(get_uid('mikewilson'), 'SAM-S24ULTRA');
$orders[] = ['id' => $id3, 'customer' => 'mikewilson', 'sku' => 'SAM-S24ULTRA'];

// Order 4: Johndoe / Apple
sleep(1);
$id4 = create_order(get_uid('johndoe'), 'APPLE-APP2');
$orders[] = ['id' => $id4, 'customer' => 'johndoe', 'sku' => 'APPLE-APP2'];

// Output IDs to file
file_put_contents('/tmp/task_order_ids.json', json_encode($orders));
echo "Created orders: " . implode(', ', array_column($orders, 'id'));
PHPEOF

echo "Executing order creation script..."
cd /var/www/html/drupal
vendor/bin/drush php:script /tmp/create_task_orders.php

# Verify the file was created
if [ ! -f /tmp/task_order_ids.json ]; then
    echo "ERROR: Failed to create task orders"
    exit 1
fi

echo "Order IDs recorded:"
cat /tmp/task_order_ids.json

# Navigate Firefox to the orders page
echo "Navigating to Orders page..."
navigate_firefox_to "http://localhost/admin/commerce/orders"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="