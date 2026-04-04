#!/bin/bash
# Export script for Setup Apparel Product Type task
# Uses Drush PHP script to inspect the complex entity relationships

echo "=== Exporting Setup Apparel Product Type Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Generate a PHP script to introspect the Drupal configuration
# We use PHP because checking entity references (attributes -> variation types)
# via raw SQL is complex and brittle.
CATALOG_INSPECTOR_PHP=/tmp/inspect_catalog.php

cat > "$CATALOG_INSPECTOR_PHP" << 'PHPEOF'
<?php

use Drupal\commerce_product\Entity\ProductAttribute;
use Drupal\commerce_product\Entity\ProductVariationType;
use Drupal\commerce_product\Entity\ProductType;
use Drupal\commerce_product\Entity\Product;

$result = [
    'timestamp' => time(),
    'attributes' => [],
    'variation_type' => null,
    'product_type' => null,
    'product' => null,
];

// 1. Inspect Attributes
foreach (['color', 'size'] as $id) {
    $attr = ProductAttribute::load($id);
    if ($attr) {
        $values = [];
        // Load values for this attribute
        $storage = \Drupal::entityTypeManager()->getStorage('commerce_product_attribute_value');
        $entities = $storage->loadByProperties(['attribute' => $id]);
        foreach ($entities as $entity) {
            $values[] = $entity->getName();
        }
        $result['attributes'][$id] = [
            'exists' => true,
            'label' => $attr->label(),
            'values' => $values
        ];
    } else {
        $result['attributes'][$id] = ['exists' => false];
    }
}

// 2. Inspect Variation Type
$varType = ProductVariationType::load('apparel');
if ($varType) {
    // Check if attribute fields exist on this variation type
    $fieldManager = \Drupal::service('entity_field.manager');
    $fields = $fieldManager->getFieldDefinitions('commerce_product_variation', 'apparel');
    
    $result['variation_type'] = [
        'exists' => true,
        'label' => $varType->label(),
        'has_color_field' => isset($fields['attribute_color']),
        'has_size_field' => isset($fields['attribute_size']),
    ];
} else {
    $result['variation_type'] = ['exists' => false];
}

// 3. Inspect Product Type
$prodType = ProductType::load('apparel');
if ($prodType) {
    $result['product_type'] = [
        'exists' => true,
        'label' => $prodType->label(),
        'variation_type_id' => $prodType->getVariationTypeId(),
    ];
} else {
    $result['product_type'] = ['exists' => false];
}

// 4. Inspect Product and Variations
$storage = \Drupal::entityTypeManager()->getStorage('commerce_product');
$products = $storage->loadByProperties(['title' => 'Urban Electronics Logo Tee']);
$product = reset($products);

if ($product) {
    $variations_data = [];
    foreach ($product->getVariations() as $variation) {
        if (!$variation->isActive()) continue;
        
        $price = $variation->getPrice();
        $variations_data[] = [
            'sku' => $variation->getSku(),
            'price' => $price ? (float) $price->getNumber() : 0,
            'currency' => $price ? $price->getCurrencyCode() : '',
            'type' => $variation->bundle(),
        ];
    }

    $result['product'] = [
        'exists' => true,
        'id' => $product->id(),
        'type' => $product->bundle(),
        'status' => (bool) $product->isPublished(),
        'variation_count' => count($variations_data),
        'variations' => $variations_data,
    ];
} else {
    // Try fuzzy search if exact title match fails
    $query = $storage->getQuery()
        ->condition('title', 'Urban Electronics Logo Tee', 'CONTAINS')
        ->accessCheck(FALSE)
        ->range(0, 1);
    $ids = $query->execute();
    if (!empty($ids)) {
         $product = $storage->load(reset($ids));
         // Logic repeated for fuzzy match (simplified)
         $result['product'] = [
            'exists' => true,
            'id' => $product->id(),
            'title_found' => $product->getTitle(),
            'is_fuzzy_match' => true
         ];
    } else {
        $result['product'] = ['exists' => false];
    }
}

echo json_encode($result, JSON_PRETTY_PRINT);
PHPEOF

# 3. Run the inspector script via Drush
cd /var/www/html/drupal
$DRUSH php:script "$CATALOG_INSPECTOR_PHP" > /tmp/task_result.json 2>/tmp/drush_error.log

# 4. Fallback: If Drush failed, create a basic error result
if [ ! -s /tmp/task_result.json ]; then
    echo "Drush script failed. Error log:"
    cat /tmp/drush_error.log
    echo '{"error": "Failed to execute introspection script"}' > /tmp/task_result.json
fi

# 5. Add timestamp info manually just in case
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
jq --arg start "$TASK_START" '.task_start_time = $start' /tmp/task_result.json > /tmp/task_result_final.json
mv /tmp/task_result_final.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json