#!/bin/bash
# Setup script for customer_revenue_vip_reward task
# Creates 8 orders across 3 customers with varying completed totals so the agent
# must build an aggregated Views report, identify the top spender, and create
# a VIP promotion for them.
echo "=== Setting up customer_revenue_vip_reward ==="

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

# ----- 1. DELETE STALE OUTPUTS AND CLEAN STATE -----
# Remove any pre-existing customer_revenue view
$DRUSH config:delete views.view.customer_revenue -y 2>/dev/null || true
$DRUSH config:delete views.view.customer-revenue -y 2>/dev/null || true
$DRUSH config:delete views.view.customer_revenue_report -y 2>/dev/null || true

# Remove any pre-existing VIP Reward promotions
VIP_PROMO_IDS=$(drupal_db_query "SELECT promotion_id FROM commerce_promotion_field_data WHERE name LIKE '%VIP Reward%' OR name LIKE '%VIP reward%'")
if [ -n "$VIP_PROMO_IDS" ]; then
    echo "Cleaning up existing VIP Reward promotions..."
    for pid in $VIP_PROMO_IDS; do
        cd "$DRUPAL_DIR" && $DRUSH php:eval "
            \$p = \Drupal\commerce_promotion\Entity\Promotion::load($pid);
            if (\$p) { \$p->delete(); echo 'Deleted promo #$pid\n'; }
        " 2>/dev/null || true
    done
fi

# Remove stale result files
rm -f /tmp/task_result.json /tmp/view_config.json /tmp/task_end_screenshot.png 2>/dev/null

# ----- 2. RECORD BASELINE STATE AND TIMESTAMP -----
INITIAL_PROMO_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data")
INITIAL_PROMO_COUNT=${INITIAL_PROMO_COUNT:-0}
echo "$INITIAL_PROMO_COUNT" > /tmp/initial_promo_count

INITIAL_COUPON_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_coupon")
INITIAL_COUPON_COUNT=${INITIAL_COUPON_COUNT:-0}
echo "$INITIAL_COUPON_COUNT" > /tmp/initial_coupon_count

INITIAL_ORDER_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_order")
INITIAL_ORDER_COUNT=${INITIAL_ORDER_COUNT:-0}
echo "$INITIAL_ORDER_COUNT" > /tmp/initial_order_count

date +%s > /tmp/task_start_timestamp

# ----- 3. SEED TEST ORDERS -----
# johndoe  (uid=2): 3 completed = $2,365.98
# janesmith (uid=3): 2 completed = $1,362.98
# mikewilson (uid=4): 1 completed + 2 canceled = $94.99 completed total
echo "Creating test orders..."
cd "$DRUPAL_DIR"
$DRUSH php:eval '
use Drupal\commerce_order\Entity\Order;
use Drupal\commerce_order\Entity\OrderItem;
use Drupal\commerce_product\Entity\ProductVariation;
use Drupal\commerce_price\Price;
use Drupal\profile\Entity\Profile;

function _seed_profile($uid, $first, $last, $line1, $city, $state, $zip) {
    $profile = Profile::create([
        "type" => "customer",
        "uid" => $uid,
        "address" => [
            "country_code" => "US",
            "given_name" => $first,
            "family_name" => $last,
            "address_line1" => $line1,
            "locality" => $city,
            "administrative_area" => $state,
            "postal_code" => $zip,
        ],
    ]);
    $profile->save();
    return $profile;
}

function _seed_order($uid, $email, $profile, $items, $state, $days_ago) {
    $order_items = [];
    foreach ($items as $item) {
        $variation = ProductVariation::load($item[0]);
        if (!$variation) {
            echo "WARNING: Variation " . $item[0] . " not found\n";
            continue;
        }
        $oi = OrderItem::create([
            "type" => "default",
            "purchased_entity" => $variation,
            "quantity" => 1,
            "unit_price" => new Price($item[1], "USD"),
            "title" => $variation->getTitle(),
        ]);
        $oi->save();
        $order_items[] = $oi;
    }
    $order = Order::create([
        "type" => "default",
        "store_id" => 1,
        "uid" => $uid,
        "mail" => $email,
        "billing_profile" => $profile,
        "order_items" => $order_items,
        "state" => $state,
        "placed" => time() - (86400 * $days_ago),
    ]);
    $order->save();
    echo "Order #" . $order->id() . " ($state) uid=$uid total=" . $order->getTotalPrice() . "\n";
}

$p2 = _seed_profile(2, "John", "Doe", "123 Elm Street", "Austin", "TX", "73301");
$p3 = _seed_profile(3, "Jane", "Smith", "456 Pine Avenue", "Portland", "OR", "97201");
$p4 = _seed_profile(4, "Mike", "Wilson", "789 Oak Drive", "Denver", "CO", "80202");

// johndoe (uid=2): 3 completed orders = $2,365.98
_seed_order(2, "john.doe@example.com", $p2, [[2,"1099.00"],[5,"99.99"]], "completed", 30);
_seed_order(2, "john.doe@example.com", $p2, [[1,"348.00"],[8,"199.00"]], "completed", 14);
_seed_order(2, "john.doe@example.com", $p2, [[6,"619.99"]], "completed", 3);

// janesmith (uid=3): 2 completed orders = $1,362.98
_seed_order(3, "jane.smith@example.com", $p3, [[3,"997.99"]], "completed", 21);
_seed_order(3, "jane.smith@example.com", $p3, [[4,"299.00"],[7,"65.99"]], "completed", 7);

// mikewilson (uid=4): 1 completed + 2 canceled = $94.99 completed
_seed_order(4, "mike.wilson@example.com", $p4, [[12,"94.99"]], "completed", 25);
_seed_order(4, "mike.wilson@example.com", $p4, [[9,"149.99"]], "canceled", 18);
_seed_order(4, "mike.wilson@example.com", $p4, [[10,"89.99"]], "canceled", 10);

echo "\nSEED COMPLETE: 8 orders created\n";
' 2>&1

# Verify orders were created
COMPLETED_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_order WHERE state='completed'")
echo "Completed orders in database: $COMPLETED_COUNT"

if [ "$COMPLETED_COUNT" -lt 6 ]; then
    echo "ERROR: Expected at least 6 completed orders, got $COMPLETED_COUNT"
    exit 1
fi

# Clear caches
cd "$DRUPAL_DIR" && $DRUSH cr 2>/dev/null || true

# ----- 4. LAUNCH APPLICATION -----
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

navigate_firefox_to "http://localhost/admin/commerce"
sleep 5

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Agent must: build aggregated Views report at /admin/commerce/customer-revenue,"
echo "read it to identify top customer, create VIP promotion, add menu link"
