#!/bin/bash
# Setup script for record_offline_payment task
echo "=== Setting up record_offline_payment ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if task_utils not fully loaded
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
    navigate_firefox_to() {
        DISPLAY=:1 xdotool key ctrl+l
        sleep 0.5
        DISPLAY=:1 xdotool type --clearmodifiers "$1"
        sleep 0.3
        DISPLAY=:1 xdotool key Return
        sleep 3
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
    ensure_services_running() {
        echo " ensuring services..." 
    }
    ensure_drupal_shown() {
        echo " ensuring drupal..."
    }
fi

# Ensure all services are running
ensure_services_running 120

# 1. Create Manual Payment Gateway if it doesn't exist
echo "Configuring Manual Payment Gateway..."
cd /var/www/html/drupal
GATEWAY_CHECK=$(./vendor/bin/drush php:eval "
use Drupal\commerce_payment\Entity\PaymentGateway;
\$gateway = PaymentGateway::load('manual');
echo \$gateway ? 'exists' : 'missing';
")

if [ "$GATEWAY_CHECK" != "exists" ]; then
    ./vendor/bin/drush php:eval "
    use Drupal\commerce_payment\Entity\PaymentGateway;
    \$gateway = PaymentGateway::create([
      'id' => 'manual',
      'label' => 'Manual / Check',
      'plugin' => 'manual',
      'configuration' => [
        'display_label' => 'Check / Money Order',
        'instructions' => [
          'value' => 'Please send checks to...',
          'format' => 'plain_text',
        ],
      ],
      'status' => 1,
    ]);
    \$gateway->save();
    echo 'Created manual gateway';
    "
else
    echo "Manual gateway already exists"
fi

# 2. Ensure user mikewilson exists
./vendor/bin/drush user:create mikewilson --mail="mike.wilson@example.com" --password="Customer123!" 2>/dev/null || true
MIKE_UID=$(drupal_db_query "SELECT uid FROM users_field_data WHERE name='mikewilson'")
echo "Mike Wilson UID: $MIKE_UID"

# 3. Create the unpaid order for Mike Wilson
echo "Creating unpaid order..."
# We use a PHP script to create a precise order state
./vendor/bin/drush php:eval "
use Drupal\commerce_order\Entity\Order;
use Drupal\commerce_order\Entity\OrderItem;
use Drupal\commerce_product\Entity\ProductVariation;
use Drupal\commerce_price\Price;

// Load user
\$uid = $MIKE_UID;
\$user = \Drupal\user\Entity\User::load(\$uid);

// Load product variation (Sony Headphones)
// Assuming variation_id 1 is SONY-WH1000XM5 from seed data
\$variation = ProductVariation::load(1);
if (!\$variation) {
    // Fallback: find any variation
    \$ids = \Drupal::entityQuery('commerce_product_variation')->range(0,1)->accessCheck(FALSE)->execute();
    \$variation = ProductVariation::load(reset(\$ids));
}

// Create Order Item (Quantity 4)
\$order_item = OrderItem::create([
  'type' => 'default',
  'purchased_entity' => \$variation,
  'quantity' => 4,
  'unit_price' => \$variation->getPrice(),
]);
\$order_item->save();

// Create Order
\$order = Order::create([
  'type' => 'default',
  'state' => 'draft',
  'mail' => \$user->getEmail(),
  'uid' => \$uid,
  'store_id' => 1,
  'order_items' => [\$order_item],
  'payment_gateway' => 'manual',
]);
\$order->save();

// Transition to fulfillment (placed) but WITHOUT payment
// We simply set the state directly to bypass workflow constraints that might require payment
\$order->set('state', 'fulfillment');
\$order->set('placed', time());
\$order->save();

echo 'Created Order #' . \$order->id() . ' Total: ' . \$order->getTotalPrice()->getNumber();
file_put_contents('/tmp/target_order_id.txt', \$order->id());
"

TARGET_ORDER_ID=$(cat /tmp/target_order_id.txt)
echo "Target Order ID: $TARGET_ORDER_ID"

# Record initial payments (should be 0)
INITIAL_PAYMENTS=$(drupal_db_query "SELECT COUNT(*) FROM commerce_payment WHERE order_id = $TARGET_ORDER_ID")
echo "$INITIAL_PAYMENTS" > /tmp/initial_payment_count

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Drupal admin page is showing
ensure_drupal_shown 60

# Navigate to Orders page
echo "Navigating to Orders page..."
navigate_firefox_to "http://localhost/admin/commerce/orders"
sleep 5

# Focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="