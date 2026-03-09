#!/bin/bash
# Export script for deploy_storefront_search task

echo "=== Exporting deploy_storefront_search Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

DRUPAL_ROOT="/var/www/html/drupal"
DRUSH="$DRUPAL_ROOT/vendor/bin/drush"
RESULT_JSON="/tmp/task_result.json"

# 1. Export the View configuration using Drush (JSON format)
echo "Exporting view configuration..."
VIEW_CONFIG="{}"
VIEW_EXISTS="false"

if cd "$DRUPAL_ROOT" && $DRUSH config:get views.view.catalog_search --format=json > /tmp/view_config.json 2>/dev/null; then
    VIEW_EXISTS="true"
    # Read the file content
    VIEW_CONFIG=$(cat /tmp/view_config.json)
else
    echo "View 'catalog_search' not found."
fi

# 2. Check the URL status code
echo "Checking URL /search/catalog..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/search/catalog)
echo "HTTP Status: $HTTP_STATUS"

# 3. Functional Search Test
# We try to search for a known SKU (e.g., LOGI-MXM3S) if the page exists
SEARCH_RESULT_SKU="false"
SEARCH_RESULT_TITLE="false"

if [ "$HTTP_STATUS" == "200" ]; then
    # Helper to find input names for filters
    # The agent might name the exposed filters anything, so we grep the HTML form
    PAGE_CONTENT=$(curl -s "http://localhost/search/catalog")
    
    # Try to identify filter query parameters from the form action/inputs
    # This is tricky without knowing exact machine names of filters. 
    # Standard exposed filters often use 'title' or 'sku' or 'field_sku_value'.
    
    # Simple test: Try common patterns for SKU search
    # We look for the text "Logitech MX Master 3S" in the result
    
    # Test 1: Search by exact SKU
    # We assume the agent might have used 'sku' or 'field_sku_value' or 'field_sku'
    for param in "sku" "field_sku_value" "field_sku" "variation_sku"; do
        RES=$(curl -s "http://localhost/search/catalog?$param=LOGI-MXM3S")
        if echo "$RES" | grep -qi "Logitech MX Master 3S"; then
            SEARCH_RESULT_SKU="true"
            break
        fi
    done

    # Test 2: Search by Title
    for param in "title" "name" "title_1"; do
        RES=$(curl -s "http://localhost/search/catalog?$param=Sony")
        if echo "$RES" | grep -qi "Sony WH-1000XM5"; then
            SEARCH_RESULT_TITLE="true"
            break
        fi
    done
fi

# 4. Check Menu Link
# Check if a menu link pointing to internal:/search/catalog exists in 'main' menu
echo "Checking menu links..."
MENU_LINK_EXISTS="false"
# Query DB for menu link content
MENU_CHECK=$(drupal_db_query "SELECT title FROM menu_link_content_data WHERE link__uri LIKE 'internal:/search/catalog' AND menu_name = 'main' LIMIT 1")
if [ -n "$MENU_CHECK" ]; then
    MENU_LINK_EXISTS="true"
fi

# 5. Prepare JSON Result
# We use python to safely construct the JSON because VIEW_CONFIG is a large JSON object
python3 -c "
import json
import os

try:
    view_config_str = '''$VIEW_CONFIG'''
    if view_config_str and view_config_str != '{}':
        view_config = json.loads(view_config_str)
    else:
        view_config = None
except:
    view_config = None

result = {
    'view_exists': '$VIEW_EXISTS' == 'true',
    'http_status': '$HTTP_STATUS',
    'view_config': view_config,
    'menu_link_exists': '$MENU_LINK_EXISTS' == 'true',
    'search_functional_sku': '$SEARCH_RESULT_SKU' == 'true',
    'search_functional_title': '$SEARCH_RESULT_TITLE' == 'true'
}

with open('$RESULT_JSON', 'w') as f:
    json.dump(result, f)
"

# Set permissions
chmod 666 "$RESULT_JSON"

echo "=== Export Complete ==="