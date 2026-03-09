#!/bin/bash
echo "=== Exporting Configure Wholesale Order Type Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# We use Drush to export the current configuration and data state directly to JSON.
# This avoids fragile SQL parsing and handles serialized data and entity relationships properly.

cd /var/www/html/drupal

# Create a PHP script to dump the state
cat > /tmp/dump_state.php << 'PHPEOF'
<?php

use Drupal\commerce_order\Entity\OrderType;
use Drupal\commerce_order\Entity\OrderItemType;
use Drupal\commerce_order\Entity\Order;
use Drupal\user\Entity\User;

// 1. Export Order Types
$order_types = [];
foreach (OrderType::loadMultiple() as $type) {
  $order_types[$type->id()] = [
    'id' => $type->id(),
    'label' => $type->label(),
    'workflow' => $type->getWorkflowId(),
  ];
}

// 2. Export Order Item Types
$order_item_types = [];
foreach (OrderItemType::loadMultiple() as $type) {
  $order_item_types[$type->id()] = [
    'id' => $type->id(),
    'label' => $type->label(),
    'purchasableEntityType' => $type->getPurchasableEntityTypeId(),
    'orderType' => $type->getOrderTypeId(),
  ];
}

// 3. Export Orders (filtering for recent ones or specific users)
$orders = [];
// Load all orders to check for the correct one
$query = \Drupal::entityQuery('commerce_order')->accessCheck(FALSE);
$ids = $query->execute();
foreach (Order::loadMultiple($ids) as $order) {
  $items = [];
  foreach ($order->getItems() as $item) {
    // Determine if purchased entity is valid
    $purchased_entity = $item->getPurchasedEntity();
    $items[] = [
      'id' => $item->id(),
      'quantity' => $item->getQuantity(),
      'title' => $item->getTitle(),
      'type' => $item->bundle(),
      'purchased_entity_type' => $purchased_entity ? $purchased_entity->getEntityTypeId() : null,
    ];
  }
  
  $orders[$order->id()] = [
    'id' => $order->id(),
    'type' => $order->bundle(),
    'uid' => $order->getCustomerId(),
    'state' => $order->getState()->value,
    'item_count' => count($items),
    'items' => $items,
    'created' => $order->getCreatedTime(),
  ];
}

// 4. Get User Info for verification
$users = [];
$uids = \Drupal::entityQuery('user')
  ->accessCheck(FALSE)
  ->condition('name', 'mikewilson')
  ->execute();
foreach (User::loadMultiple($uids) as $user) {
  $users[$user->getAccountName()] = $user->id();
}

$result = [
  'order_types' => $order_types,
  'order_item_types' => $order_item_types,
  'orders' => $orders,
  'target_users' => $users,
  'timestamp' => time(),
];

echo json_encode($result, JSON_PRETTY_PRINT);
PHPEOF

# Run the PHP script via Drush and save to result file
echo "Exporting Drupal state..."
vendor/bin/drush php:eval "$(cat /tmp/dump_state.php)" > /tmp/task_result.json 2> /tmp/drush_error.log

# Check if export succeeded
if [ ! -s /tmp/task_result.json ]; then
    echo "ERROR: Failed to export data via Drush."
    cat /tmp/drush_error.log
    # Create a fallback/failure JSON
    echo '{"error": "Export failed"}' > /tmp/task_result.json
fi

# Set permissions so the host user can read it
chmod 666 /tmp/task_result.json

echo "Export complete."
cat /tmp/task_result.json | head -n 20
echo "..."