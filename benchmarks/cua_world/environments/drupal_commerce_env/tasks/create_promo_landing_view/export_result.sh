#!/bin/bash
# Export script for create_promo_landing_view task

echo "=== Exporting Create Promo Landing View Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. HTTP Verification: Check if the page exists and contains expected content
TARGET_URL="http://localhost/pro-audio"
echo "Checking URL: $TARGET_URL"

# Curl the page, following redirects, verify SSL off, max time 10s
HTTP_CONTENT=$(curl -sL --max-time 10 "$TARGET_URL")
HTTP_STATUS=$(curl -sL -o /dev/null -w "%{http_code}" --max-time 10 "$TARGET_URL")

echo "HTTP Status: $HTTP_STATUS"

# Check for specific content strings in the HTML output
HAS_HEADER_TEXT="false"
HAS_POSITIVE_PRODUCT="false"
HAS_NEGATIVE_PRODUCT="false"

if echo "$HTTP_CONTENT" | grep -q "Upgrade your setup with our professional gear"; then
    HAS_HEADER_TEXT="true"
fi

# Check for "AirPods Pro" (should exist)
if echo "$HTTP_CONTENT" | grep -q "AirPods Pro"; then
    HAS_POSITIVE_PRODUCT="true"
fi

# Check for "MX Master" (should NOT exist if filter works)
if echo "$HTTP_CONTENT" | grep -q "MX Master"; then
    HAS_NEGATIVE_PRODUCT="true"
fi

# 2. Configuration Verification: Inspect Views config via Drush
# We need to find which view is serving this path to verify settings
echo "Inspecting Views configuration..."

# PHP script to find the view with the correct path and dump its config
VIEW_CONFIG_JSON=$($DRUSH php:eval '
use Drupal\views\Views;
$result = ["found" => false];

$all_views = Views::getAllViews();
foreach ($all_views as $view) {
    if ($view->isDisabled()) continue;
    
    // Check all displays
    foreach ($view->get("display") as $display_id => $display) {
        if (isset($display["display_options"]["path"]) && $display["display_options"]["path"] == "pro-audio") {
            $result["found"] = true;
            $result["view_id"] = $view->id();
            $result["label"] = $view->label();
            
            // Check filters
            $filters = $display["display_options"]["filters"] ?? [];
            // If display uses default filters, grab them from default display
            if (empty($filters) && isset($view->get("display")["default"]["display_options"]["filters"])) {
                 $filters = $view->get("display")["default"]["display_options"]["filters"];
            }
            $result["filters"] = $filters;
            
            // Check header
            $header = $display["display_options"]["header"] ?? [];
             if (empty($header) && isset($view->get("display")["default"]["display_options"]["header"])) {
                 $header = $view->get("display")["default"]["display_options"]["header"];
            }
            $result["header"] = $header;
            
            // Check menu
            $menu = $display["display_options"]["menu"] ?? [];
            $result["menu"] = $menu;
            
            break 2;
        }
    }
}
echo json_encode($result);
' 2>/dev/null)

# 3. Check Main Menu for link
# Verify if a menu link exists in the main menu pointing to internal:/pro-audio
MENU_LINK_JSON=$($DRUSH php:eval '
$menu_tree = \Drupal::menuTree();
$parameters = new \Drupal\Core\Menu\MenuTreeParameters();
$tree = $menu_tree->load("main", $parameters);

$found = false;
$title = "";

foreach ($tree as $element) {
    $link = $element->link;
    $url = $link->getUrlObject();
    if ($url->isRouted()) {
        // Internal route check might be complex, check uri string
        $uri = $link->getUrlObject()->toUriString(); 
        // Typically "route:view.view_id.display_id" or "internal:/pro-audio"
    }
    
    // Simpler check: Title matching "Pro Audio"
    if ($link->getTitle() == "Pro Audio") {
        $found = true;
        $title = $link->getTitle();
        break;
    }
}
echo json_encode(["found" => $found, "title" => $title]);
' 2>/dev/null)

# Build result JSON
create_result_json /tmp/task_result.json \
    "http_status=$HTTP_STATUS" \
    "content_header_found=$HAS_HEADER_TEXT" \
    "content_positive_product_found=$HAS_POSITIVE_PRODUCT" \
    "content_negative_product_found=$HAS_NEGATIVE_PRODUCT" \
    "view_config_found=$(echo "$VIEW_CONFIG_JSON" | jq -r '.found // false')" \
    "view_id=$(echo "$VIEW_CONFIG_JSON" | jq -r '.view_id // ""')" \
    "menu_link_found=$(echo "$MENU_LINK_JSON" | jq -r '.found // false')"

# Embed the raw view config structure for python to parse complexity if needed
# (Using a temp file for the raw JSON to avoid quoting hell)
echo "$VIEW_CONFIG_JSON" > /tmp/view_config_raw.json

# Merge raw config into result using jq if available, or just leave it for python to load separately?
# We'll just append the raw config file content to a specific key if possible, 
# but simply providing the extracted boolean flags above is often safer for bash.
# We will rely on verifier to read /tmp/task_result.json. 
# We'll also save the raw config to a separate file for the verifier to load.

chmod 666 /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/view_config_raw.json 2>/dev/null || true

echo "Result JSON:"
cat /tmp/task_result.json

echo "=== Export Complete ==="