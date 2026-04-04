#!/bin/bash
# Export script for configure_tiered_promotions
# This script runs a PHP simulation to verify the actual pricing logic

echo "=== Exporting Tiered Promotions Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Create a PHP script to simulate carts and verify logic
# We use a temporary PHP script that bootstraps Drupal and runs the pricing engine
CAT_SIMULATION_SCRIPT="/tmp/verify_tiers.php"

cat > "$CAT_SIMULATION_SCRIPT" << 'PHPEOF'
<?php

use Drupal\commerce_order\Entity\Order;
use Drupal\commerce_price\Price;
use Drupal\commerce_store\Entity\Store;
use Drupal\commerce_product\Entity\ProductVariation;
use Drupal\commerce_order\Entity\OrderItem;

// Output array
$results = [
    'tier1_exists' => false,
    'tier2_exists' => false,
    'scenario_150' => 0,
    'scenario_400' => 0,
    'promotions_applied_150' => [],
    'promotions_applied_400' => [],
];

// 1. Check if promotions exist in DB
$query = \Drupal::entityQuery('commerce_promotion');
$ids = $query->condition('status', TRUE)->execute();
$promotions = \Drupal::entityTypeManager()->getStorage('commerce_promotion')->loadMultiple($ids);

foreach ($promotions as $promo) {
    $label = $promo->label();
    $offer = $promo->getOffer();
    $offer_config = $offer->getConfiguration();
    
    // Loose checking for existence
    if (strpos($label, '15') !== false || (isset($offer_config['amount']['number']) && $offer_config['amount']['number'] == 15)) {
        $results['tier1_exists'] = true;
    }
    if (strpos($label, '50') !== false || (isset($offer_config['amount']['number']) && $offer_config['amount']['number'] == 50)) {
        $results['tier2_exists'] = true;
    }
}

// 2. Simulation Helper
function get_adjustments_for_amount($amount_number) {
    $store = Store::load(1); // Default store
    $order_type = 'default';
    
    // Create a temporary order (not saved)
    $order = Order::create([
        'type' => $order_type,
        'store_id' => $store->id(),
        'uid' => 0, // Anonymous
        'state' => 'draft',
    ]);
    
    // We need a purchasable entity. Grab the first one found.
    $variations = \Drupal::entityTypeManager()->getStorage('commerce_product_variation')->loadByProperties(['status' => 1]);
    $variation = reset($variations);
    
    if (!$variation) {
        return ['error' => 'No variations found'];
    }

    // Create order item with overridden price to match our test case
    $order_item = OrderItem::create([
        'type' => 'default',
        'purchased_entity' => $variation,
        'quantity' => 1,
        'unit_price' => new Price((string)$amount_number, 'USD'),
        'overridden_unit_price' => true,
    ]);
    $order_item->save();
    
    $order->addItem($order_item);
    
    // Run the order refresh process which triggers promotions
    $order_refresh = \Drupal::service('commerce_order.order_refresh');
    $order_refresh->refresh($order);
    
    // Calculate total discount
    $total_discount = 0;
    $applied_promos = [];
    
    foreach ($order->getAdjustments() as $adjustment) {
        if ($adjustment->getType() == 'promotion') {
            $amount = $adjustment->getAmount();
            // Adjustments are usually negative for discounts
            $total_discount += abs($amount->getNumber());
            $applied_promos[] = $adjustment->getLabel();
        }
    }
    
    // Also check order items adjustments (promotions can apply to items or order)
    foreach ($order->getItems() as $item) {
        foreach ($item->getAdjustments() as $adjustment) {
            if ($adjustment->getType() == 'promotion') {
                $amount = $adjustment->getAmount();
                $total_discount += abs($amount->getNumber());
                $applied_promos[] = $adjustment->getLabel();
            }
        }
    }
    
    return [
        'discount' => $total_discount,
        'promos' => array_unique($applied_promos)
    ];
}

// 3. Run Scenarios
try {
    $res150 = get_adjustments_for_amount(150.00);
    $results['scenario_150'] = $res150['discount'];
    $results['promotions_applied_150'] = $res150['promos'];
    
    $res400 = get_adjustments_for_amount(400.00);
    $results['scenario_400'] = $res400['discount'];
    $results['promotions_applied_400'] = $res400['promos'];
} catch (\Exception $e) {
    $results['error'] = $e->getMessage();
}

echo json_encode($results);
PHPEOF

# Execute the PHP script via Drush
echo "Running verification simulation..."
cd /var/www/html/drupal
# We use drush php:script to run it within the bootstrapped Drupal environment
SIMULATION_OUTPUT=$(vendor/bin/drush php:script "$CAT_SIMULATION_SCRIPT" 2>/dev/null)

# Fallback if drush fails silently or outputs extra text
# Extract JSON object from output (find first { and last })
JSON_OUTPUT=$(echo "$SIMULATION_OUTPUT" | grep -o "{.*}")

if [ -z "$JSON_OUTPUT" ]; then
    # Try generic DB query backup if simulation completely failed
    echo "Simulation failed, falling back to DB check..."
    TIER1_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data WHERE status=1 AND (name LIKE '%15%' OR name LIKE '%Tier 1%')")
    TIER2_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data WHERE status=1 AND (name LIKE '%50%' OR name LIKE '%Tier 2%')")
    
    # Construct a basic JSON
    JSON_OUTPUT="{\"tier1_exists\": $([ "$TIER1_COUNT" -gt 0 ] && echo "true" || echo "false"), \"tier2_exists\": $([ "$TIER2_COUNT" -gt 0 ] && echo "true" || echo "false"), \"simulation_failed\": true}"
fi

# Save to result file
echo "$JSON_OUTPUT" > /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON:"
cat /tmp/task_result.json

echo "=== Export Complete ==="