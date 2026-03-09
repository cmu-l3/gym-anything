#!/bin/bash
# Setup script for optimize_product_page_layout
# Ensures the Product Variation display is in the "broken" state (SKU hidden, Image medium)

echo "=== Setting up Optimize Product Page Layout Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
ensure_services_running 90

# 1. Enforce the "Starting State" via Drush PHP
# SKU hidden, Image style = medium
echo "Configuring initial display state (SKU hidden, Image medium)..."
cd /var/www/html/drupal
$DRUSH php:eval '
use Drupal\Core\Entity\Entity\EntityViewDisplay;

$display = \Drupal::entityTypeManager()->getStorage("entity_view_display")->load("commerce_product_variation.default.default");
if (!$display) {
    // Create if missing (unlikely in standard install, but safe)
    $display = EntityViewDisplay::create([
        "targetEntityType" => "commerce_product_variation",
        "bundle" => "default",
        "mode" => "default",
        "status" => TRUE,
    ]);
}

// Hide SKU
$display->removeComponent("sku");

// Set Image to medium
$display->setComponent("field_images", [
    "type" => "image",
    "weight" => 0,
    "region" => "content",
    "label" => "hidden",
    "settings" => [
        "image_link" => "",
        "image_style" => "medium", // 220x220
    ],
    "third_party_settings" => [],
]);

$display->save();
echo "Display configuration reset successfully.\n";
'

# 2. Record the initial config hash to detect changes later
echo "Recording initial config hash..."
INITIAL_HASH=$($DRUSH config:get core.entity_view_display.commerce_product_variation.default.default --format=yaml | md5sum | awk '{print $1}')
echo "$INITIAL_HASH" > /tmp/initial_config_hash.txt
echo "Initial Hash: $INITIAL_HASH"

# 3. Prepare Firefox
echo "Ensuring Drupal admin is displayed..."
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Navigate to the Commerce Dashboard or Configuration page
# Providing a helpful starting point, but not the exact page (task requires navigation)
navigate_firefox_to "http://localhost/admin/commerce/config"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="