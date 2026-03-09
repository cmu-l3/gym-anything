#!/bin/bash
# Setup script for process_customer_refund task
# Creates a placed order for johndoe that the agent must cancel and refund
echo "=== Setting up process_customer_refund ==="

. /workspace/scripts/task_utils.sh

if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

ensure_services_running 120

DRUPAL_DIR="/var/www/html/drupal"
DRUSH="$DRUPAL_DIR/vendor/bin/drush"

# Create the order for johndoe using Drush PHP
echo "Creating order for johndoe..."
cd "$DRUPAL_DIR"
$DRUSH php:eval '
use Drupal\commerce_order\Entity\Order;
use Drupal\commerce_order\Entity\OrderItem;
use Drupal\commerce_product\Entity\ProductVariation;
use Drupal\commerce_price\Price;
use Drupal\profile\Entity\Profile;

// Create billing profile for johndoe
$profile = Profile::create([
    "type" => "customer",
    "uid" => 2,
    "address" => [
        "country_code" => "US",
        "given_name" => "John",
        "family_name" => "Doe",
        "address_line1" => "123 Elm Street",
        "locality" => "Austin",
        "administrative_area" => "TX",
        "postal_code" => "73301",
    ],
]);
$profile->save();

// MacBook Air M2 (variation_id=2, $1099.00)
$macbook_var = ProductVariation::load(2);
$item1 = OrderItem::create([
    "type" => "default",
    "purchased_entity" => $macbook_var,
    "quantity" => 1,
    "unit_price" => new Price("1099.00", "USD"),
]);
$item1->save();

// Keychron Q1 Pro (variation_id=8, $199.00)
$keychron_var = ProductVariation::load(8);
$item2 = OrderItem::create([
    "type" => "default",
    "purchased_entity" => $keychron_var,
    "quantity" => 1,
    "unit_price" => new Price("199.00", "USD"),
]);
$item2->save();

// Create the order in "completed" state (already placed)
$order = Order::create([
    "type" => "default",
    "store_id" => 1,
    "uid" => 2,
    "mail" => "john.doe@example.com",
    "billing_profile" => $profile,
    "order_items" => [$item1, $item2],
    "state" => "completed",
    "placed" => time() - 86400,
]);
$order->save();

echo "Order created: #" . $order->id() . " for johndoe, total: $" . $order->getTotalPrice()->getNumber() . "\n";
' 2>&1

# Verify the order was created
ORDER_ID=$(drupal_db_query "SELECT order_id FROM commerce_order WHERE uid=2 AND state='completed' ORDER BY order_id DESC LIMIT 1")
echo "Created order ID: $ORDER_ID"

if [ -z "$ORDER_ID" ]; then
    echo "ERROR: Failed to create order for johndoe"
    exit 1
fi

echo "$ORDER_ID" > /tmp/refund_order_id

# Record baseline state
INITIAL_PROMO_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data")
INITIAL_PROMO_COUNT=${INITIAL_PROMO_COUNT:-0}
echo "$INITIAL_PROMO_COUNT" > /tmp/initial_promo_count

INITIAL_COUPON_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_coupon")
INITIAL_COUPON_COUNT=${INITIAL_COUPON_COUNT:-0}
echo "$INITIAL_COUPON_COUNT" > /tmp/initial_coupon_count

INITIAL_ORDER_STATE=$(drupal_db_query "SELECT state FROM commerce_order WHERE order_id=$ORDER_ID")
echo "$INITIAL_ORDER_STATE" > /tmp/initial_order_state

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Navigate Firefox to orders admin
navigate_firefox_to "http://localhost/admin/commerce/orders"
sleep 5

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Order #$ORDER_ID created for johndoe (completed state, $1,298.00 total)"
echo "Agent must: cancel order, create store credit promotion with REFUND-JOHNDOE coupon"
