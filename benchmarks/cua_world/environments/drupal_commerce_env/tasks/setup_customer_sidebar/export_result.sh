#!/bin/bash
# Export script for setup_customer_sidebar task

echo "=== Exporting setup_customer_sidebar Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create a PHP script to extract detailed block configuration
# This is much more reliable than parsing raw config files or SQL
cat > /tmp/export_blocks.php << 'PHPEOF'
<?php
use Drupal\block\Entity\Block;

// Get default theme
$theme = \Drupal::config('system.theme')->get('default');
$results = [
    'theme' => $theme,
    'sidebar_blocks' => [],
    'custom_block_created' => false,
    'custom_block_content' => '',
];

// 1. Analyze Blocks in Sidebar Region
$blocks = \Drupal::entityTypeManager()->getStorage('block')->loadByProperties([
    'theme' => $theme,
    'region' => 'sidebar' // Olivero uses 'sidebar', Bartik 'sidebar_first' usually.
]);

// If sidebar is empty, check sidebar_first just in case theme differs
if (empty($blocks)) {
    $blocks = \Drupal::entityTypeManager()->getStorage('block')->loadByProperties([
        'theme' => $theme,
        'region' => 'sidebar_first'
    ]);
}

foreach ($blocks as $block) {
    $visibility = $block->getVisibility();
    
    // Extract plugin-specific configuration
    $plugin_id = $block->getPluginId();
    $settings = $block->get('settings');
    
    // Check if this is a block content block (custom block)
    $content_body = '';
    if (strpos($plugin_id, 'block_content:') === 0) {
        $uuid = str_replace('block_content:', '', $plugin_id);
        $content_block = \Drupal::service('entity.repository')->loadEntityByUuid('block_content', $uuid);
        if ($content_block && $content_block->hasField('body')) {
            $content_body = $content_block->body->value;
        }
    }

    $results['sidebar_blocks'][] = [
        'id' => $block->id(),
        'label' => $block->label(),
        'plugin_id' => $plugin_id,
        'region' => $block->getRegion(),
        'weight' => $block->getWeight(),
        'visibility' => [
            'user_role' => $visibility['user_role'] ?? [],
            'request_path' => $visibility['request_path'] ?? [],
        ],
        'content_body' => $content_body
    ];
}

// 2. Check if the Custom Block entity exists at all (even if not placed)
$query = \Drupal::entityQuery('block_content')
    ->condition('info', 'Sidebar Support', 'CONTAINS')
    ->accessCheck(FALSE);
$ids = $query->execute();

if (!empty($ids)) {
    $results['custom_block_created'] = true;
    $block = \Drupal::entityTypeManager()->getStorage('block_content')->load(reset($ids));
    if ($block && $block->hasField('body')) {
        $results['custom_block_content'] = $block->body->value;
    }
}

echo json_encode($results, JSON_PRETTY_PRINT);
PHPEOF

# Execute the PHP script via Drush
echo "Extracting block configuration..."
$DRUSH php:eval "$(cat /tmp/export_blocks.php)" > /tmp/block_config.json 2>/dev/null

# Get app running status
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $(cat /tmp/task_start_timestamp 2>/dev/null || echo "0"),
    "task_end": $(date +%s),
    "app_was_running": $APP_RUNNING,
    "initial_block_count": $(cat /tmp/initial_sidebar_block_count 2>/dev/null || echo "0"),
    "screenshot_path": "/tmp/task_final.png",
    "drupal_data": $(cat /tmp/block_config.json || echo "{}")
}
EOF

# Safe copy to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="