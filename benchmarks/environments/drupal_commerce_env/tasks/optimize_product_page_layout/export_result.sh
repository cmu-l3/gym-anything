#!/bin/bash
# Export script for optimize_product_page_layout
# Extracts the final configuration of the product variation display

echo "=== Exporting Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check timestamps/hash to see if config changed
INITIAL_HASH=$(cat /tmp/initial_config_hash.txt 2>/dev/null || echo "0")
CURRENT_HASH=$($DRUSH config:get core.entity_view_display.commerce_product_variation.default.default --format=yaml | md5sum | awk '{print $1}')

CONFIG_CHANGED="false"
if [ "$INITIAL_HASH" != "$CURRENT_HASH" ]; then
    CONFIG_CHANGED="true"
fi

# 2. Extract specific settings using Drush PHP for precise validation
# We need to know:
# - Is SKU in the 'content' array?
# - Is field_images['settings']['image_style'] == 'large'?
echo "Extracting configuration details..."
cd /var/www/html/drupal

# Use a temporary file for the PHP output to avoid pipe issues
PHP_RESULT_FILE="/tmp/php_config_export.json"

$DRUSH php:eval '
$display = \Drupal::entityTypeManager()->getStorage("entity_view_display")->load("commerce_product_variation.default.default");
$content = $display->get("content");

$output = [
    "sku_visible" => isset($content["sku"]),
    "sku_region" => $content["sku"]["region"] ?? "hidden",
    "image_component_exists" => isset($content["field_images"]),
    "image_style" => $content["field_images"]["settings"]["image_style"] ?? "unknown",
    "config_changed" => ('$CONFIG_CHANGED'),
    "timestamp" => time()
];
echo json_encode($output);
' > "$PHP_RESULT_FILE"

# 3. Create the final result JSON
# We merge the PHP output with our standard export fields
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat "$PHP_RESULT_FILE" > "$TEMP_JSON"

# Move to final location (handling permissions)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON" "$PHP_RESULT_FILE"

echo "Result exported:"
cat /tmp/task_result.json

echo "=== Export Complete ==="