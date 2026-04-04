#!/bin/bash
# Export script for Configure Bundle Promotion
echo "=== Exporting Configure Bundle Promotion Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# We use a PHP script via Drush to introspect the promotion entities.
# This is much more reliable than SQL for checking serialized conditions.
cat > /tmp/inspect_promotion.php << 'PHPEOF'
<?php

use Drupal\commerce_promotion\Entity\Promotion;
use Drupal\commerce_product\Entity\ProductVariation;

$results = [
    'found' => false,
    'status' => false,
    'label' => '',
    'offer_type' => '',
    'offer_amount' => 0.0,
    'offer_target_products' => [],
    'condition_trigger_products' => [],
    'created_time' => 0
];

// Load promotion by name
$promotions = \Drupal::entityTypeManager()->getStorage('commerce_promotion')->loadByProperties(['name' => 'Drone Power Bundle']);
$promotion = reset($promotions);

if ($promotion) {
    $results['found'] = true;
    $results['status'] = (bool) $promotion->isPublished();
    $results['label'] = $promotion->label();
    $results['created_time'] = (int) $promotion->getCreatedTime();

    // Inspect Offer
    $offer = $promotion->getOffer();
    $results['offer_type'] = $offer->getPluginId(); // e.g., order_item_percentage_off
    $config = $offer->getConfiguration();
    
    // Amount
    if (isset($config['percentage'])) {
        $results['offer_amount'] = (float) $config['percentage'];
    } elseif (isset($config['amount']['number'])) {
        $results['offer_amount'] = (float) $config['amount']['number'];
    }

    // Inspect Offer Conditions (Targeting)
    // For 'order_item_percentage_off', conditions determine which items get discount
    if (isset($config['conditions'])) {
        foreach ($config['conditions'] as $condition) {
            if ($condition['plugin'] == 'order_item_product_variation') {
                $results['offer_target_products'] = array_merge($results['offer_target_products'], $condition['configuration']['variations']);
            }
            // Sometimes it targets products, not variations
            if ($condition['plugin'] == 'order_item_product') {
                $results['offer_target_products'] = array_merge($results['offer_target_products'], $condition['configuration']['products']);
            }
        }
    }

    // Inspect Promotion Conditions (Triggering)
    // Check if cart has specific products
    foreach ($promotion->getConditions() as $condition) {
        $pluginId = $condition->getPluginId();
        $condConfig = $condition->getConfiguration();
        
        // order_item_quantity or order_contains_product are common triggers
        if ($pluginId == 'order_has_product_variation' || $pluginId == 'order_item_quantity') {
             if (isset($condConfig['variations'])) {
                 $results['condition_trigger_products'] = array_merge($results['condition_trigger_products'], $condConfig['variations']);
             }
        }
        if ($pluginId == 'order_has_product') {
             if (isset($condConfig['products'])) {
                 $results['condition_trigger_products'] = array_merge($results['condition_trigger_products'], $condConfig['products']);
             }
        }
    }
}

// Helper to resolve IDs to SKUs
function resolve_skus($ids) {
    if (empty($ids)) return [];
    $skus = [];
    $variations = \Drupal::entityTypeManager()->getStorage('commerce_product_variation')->loadMultiple($ids);
    foreach ($variations as $v) {
        $skus[] = $v->getSku();
    }
    // Also check products if IDs were products (less common for targeting specific SKUs but possible)
    $products = \Drupal::entityTypeManager()->getStorage('commerce_product')->loadMultiple($ids);
    foreach ($products as $p) {
        $p_variations = $p->getVariations();
        foreach ($p_variations as $v) {
            $skus[] = $v->getSku();
        }
    }
    return array_unique($skus);
}

// Resolve collected IDs to SKUs for verification
$results['offer_target_skus'] = resolve_skus($results['offer_target_products']);
$results['condition_trigger_skus'] = resolve_skus($results['condition_trigger_products']);

echo json_encode($results, JSON_PRETTY_PRINT);
PHPEOF

# Execute inspection
cd /var/www/html/drupal
vendor/bin/drush php:script /tmp/inspect_promotion.php > /tmp/promotion_data.json 2>/dev/null

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_promo_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data")

# Combine into final result
cat > /tmp/temp_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "current_count": ${CURRENT_COUNT:-0},
    "promotion_data": $(cat /tmp/promotion_data.json || echo "{}")
}
EOF

# Move to safe location
mv /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result JSON generated:"
cat /tmp/task_result.json

echo "=== Export Complete ==="