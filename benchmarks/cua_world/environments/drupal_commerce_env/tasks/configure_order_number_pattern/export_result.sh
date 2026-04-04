#!/bin/bash
# Export script for configure_order_number_pattern task
echo "=== Exporting configure_order_number_pattern Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Prepare the export file
RESULT_FILE="/tmp/task_result.json"

# We use Drush and a PHP script to export the exact configuration structure
# This avoids parsing complex serialized data in SQL or text output
echo "Exporting configuration data..."

cd /var/www/html/drupal

# Create a PHP script to dump the relevant config entities as JSON
cat > /tmp/export_config.php << 'PHPEOF'
<?php

use Drupal\commerce_number_pattern\Entity\NumberPattern;
use Drupal\commerce_order\Entity\OrderType;

$result = [
    'patterns' => [],
    'default_order_type' => [],
    'timestamp' => time(),
];

// 1. Export all Number Patterns
try {
    $storage = \Drupal::entityTypeManager()->getStorage('commerce_number_pattern');
    $patterns = $storage->loadMultiple();
    
    foreach ($patterns as $pattern) {
        $plugin = $pattern->getPlugin();
        $config = $plugin->getConfiguration();
        
        $result['patterns'][$pattern->id()] = [
            'id' => $pattern->id(),
            'label' => $pattern->label(),
            'plugin_id' => $pattern->getPluginId(),
            'target_entity_type' => $pattern->getTargetEntityTypeId(),
            'configuration' => [
                'pattern' => $config['pattern'] ?? '',
                'padding' => $config['padding'] ?? 0,
                'initial_number' => $config['initial_number'] ?? 1,
                'per_store_sequence' => $config['per_store_sequence'] ?? FALSE,
            ],
            // Check if it's new (created/changed recently is hard to track perfectly via API, 
            // so we rely on comparison with baseline in the verifier)
        ];
    }
} catch (\Exception $e) {
    $result['error_patterns'] = $e->getMessage();
}

// 2. Export Default Order Type Configuration
try {
    $order_type = OrderType::load('default');
    if ($order_type) {
        $result['default_order_type'] = [
            'id' => $order_type->id(),
            'number_pattern_id' => $order_type->getNumberPatternId(),
        ];
    }
} catch (\Exception $e) {
    $result['error_order_type'] = $e->getMessage();
}

// 3. Include initial patterns for diffing
$initial_patterns_file = '/tmp/initial_patterns.json';
if (file_exists($initial_patterns_file)) {
    $result['initial_patterns_list'] = json_decode(file_get_contents($initial_patterns_file), true);
} else {
    $result['initial_patterns_list'] = [];
}

echo json_encode($result, JSON_PRETTY_PRINT);
PHPEOF

# Run the PHP script via Drush and save output
vendor/bin/drush php:script /tmp/export_config.php > "$RESULT_FILE" 2> /tmp/export_error.log

# Set permissions so the host can read it via copy_from_env
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Export result saved to $RESULT_FILE"
echo "=== Export Complete ==="