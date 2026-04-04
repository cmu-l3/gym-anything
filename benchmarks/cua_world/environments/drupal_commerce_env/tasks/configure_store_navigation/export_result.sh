#!/bin/bash
# Export script for Configure Store Navigation task

echo "=== Exporting Configure Store Navigation Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# We use Drush to execute a PHP script that inspects the Drupal entities directly.
# This is more robust than raw SQL for things like 'which region is this block in?'
# which requires parsing config objects.

RESULT_JSON="/tmp/task_result.json"
PHP_SCRIPT="/tmp/inspect_navigation.php"

cat > "$PHP_SCRIPT" << 'PHPEOF'
<?php
use Drupal\menu_link_content\Entity\MenuLinkContent;
use Drupal\block_content\Entity\BlockContent;
use Drupal\block\Entity\Block;

$result = [
    'menu_links' => [],
    'custom_blocks' => [],
    'placed_blocks' => [],
    'timestamp' => time(),
];

// 1. Inspect Main Menu Links
// We look for enabled links in the 'main' menu
$mids = \Drupal::entityQuery('menu_link_content')
    ->condition('menu_name', 'main')
    ->accessCheck(FALSE)
    ->execute();

if (!empty($mids)) {
    $links = MenuLinkContent::loadMultiple($mids);
    foreach ($links as $link) {
        if ($link->isEnabled()) {
            $url_obj = $link->getUrlObject();
            $path = '';
            if ($url_obj->isRouted()) {
                $path = '/' . $url_obj->getInternalPath();
            } else {
                $path = $url_obj->getUri();
            }
            
            $result['menu_links'][] = [
                'id' => $link->id(),
                'title' => $link->getTitle(),
                'path' => $path,
                'weight' => (int) $link->getWeight(),
                'changed' => (int) $link->getChangedTime(),
            ];
        }
    }
}

// 2. Inspect Custom Block Content (The actual text)
$bids = \Drupal::entityQuery('block_content')
    ->accessCheck(FALSE)
    ->execute();

if (!empty($bids)) {
    $blocks = BlockContent::loadMultiple($bids);
    foreach ($blocks as $block) {
        $body_val = '';
        if ($block->hasField('body') && !$block->get('body')->isEmpty()) {
            $body_val = $block->get('body')->value;
        }
        
        $result['custom_blocks'][] = [
            'id' => $block->id(),
            'uuid' => $block->uuid(),
            'info' => $block->label(),
            'body' => $body_val,
            'changed' => (int) $block->getChangedTime(),
        ];
    }
}

// 3. Inspect Block Placement (The configuration in the theme)
// We look for blocks placed in the 'olivero' theme
$placed_blocks = \Drupal::entityTypeManager()->getStorage('block')->loadByProperties(['theme' => 'olivero']);

foreach ($placed_blocks as $pb) {
    if ($pb->status()) {
        $plugin_id = $pb->getPluginId();
        
        $result['placed_blocks'][] = [
            'id' => $pb->id(),
            'region' => $pb->getRegion(),
            'plugin_id' => $plugin_id,
            'settings' => $pb->get('settings'),
        ];
    }
}

echo json_encode($result, JSON_PRETTY_PRINT);
PHPEOF

# Execute the PHP script via Drush and save output
# We run this inside the Drupal directory
cd /var/www/html/drupal
vendor/bin/drush php:script "$PHP_SCRIPT" > "$RESULT_JSON" 2> /tmp/drush_error.log

# Ensure the file exists and has content
if [ ! -s "$RESULT_JSON" ]; then
    echo "ERROR: Drush script failed to produce output."
    echo "Drush Errors:"
    cat /tmp/drush_error.log
    # Fallback minimal JSON
    echo '{"error": "Export failed"}' > "$RESULT_JSON"
fi

# Add task timing info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
# We append this using jq if available, or simple python script, or just leave it for verifier to read from file
# The PHP script output is the primary data source.

echo "Export completed. Result size: $(stat -c %s "$RESULT_JSON") bytes"