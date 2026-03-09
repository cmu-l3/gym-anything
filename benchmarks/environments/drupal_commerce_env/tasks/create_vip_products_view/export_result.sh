#!/bin/bash
# Export script for Create VIP Products View task
# Inspects Drupal configuration using Drush and DB queries

echo "=== Exporting VIP Products View Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Verify Taxonomy Term Creation
echo "Checking taxonomy term 'VIP'..."
VIP_TERM_ID=$(drupal_db_query "SELECT tid FROM taxonomy_term_field_data WHERE vid='product_categories' AND name='VIP' LIMIT 1")
TERM_EXISTS="false"
if [ -n "$VIP_TERM_ID" ]; then
    TERM_EXISTS="true"
    echo "Found VIP term ID: $VIP_TERM_ID"
else
    echo "VIP term not found."
fi

# 2. Verify Product Tagging
# We need to check if specific products have the VIP term applied
# commerce_product__field_product_categories links product_id (entity_id) to term_id (field_product_categories_target_id)

SONY_TAGGED="false"
LOGI_TAGGED="false"

if [ "$TERM_EXISTS" = "true" ]; then
    # Get Product IDs
    SONY_PID=$(get_product_id_by_title "Sony WH-1000XM5 Wireless Headphones")
    LOGI_PID=$(get_product_id_by_title "Logitech MX Master 3S Wireless Mouse")

    if [ -n "$SONY_PID" ]; then
        CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product__field_product_categories WHERE entity_id='$SONY_PID' AND field_product_categories_target_id='$VIP_TERM_ID'")
        if [ "$CHECK" -gt 0 ]; then SONY_TAGGED="true"; fi
    fi

    if [ -n "$LOGI_PID" ]; then
        CHECK=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product__field_product_categories WHERE entity_id='$LOGI_PID' AND field_product_categories_target_id='$VIP_TERM_ID'")
        if [ "$CHECK" -gt 0 ]; then LOGI_TAGGED="true"; fi
    fi
fi

# 3. Verify View Configuration using Drush PHP Eval
# This is robust because it queries the Drupal API directly rather than parsing raw config blobs
echo "Inspecting View configuration..."

# Create a temporary PHP script to inspect views
cat > /tmp/inspect_view.php << 'PHPEOF'
use Drupal\views\Views;
use Drupal\views\Entity\View;

$results = [
    'view_found' => false,
    'path_correct' => false,
    'access_restricted' => false,
    'grid_format' => false,
    'filter_correct' => false,
    'view_id' => '',
];

$all_views = View::loadMultiple();
foreach ($all_views as $view) {
    if (!$view->status()) continue; // Skip disabled views
    
    $executable = $view->getExecutable();
    $executable->initDisplay();
    
    foreach ($executable->displayHandlers as $display_id => $display) {
        // Check if this display has the correct path
        if ($display->hasPath() && $display->getPath() == 'vip-products') {
            $results['view_found'] = true;
            $results['path_correct'] = true;
            $results['view_id'] = $view->id();
            
            // Check Access
            $access = $display->getOption('access');
            // Look for role-based access
            if (isset($access['type']) && $access['type'] == 'role') {
                $roles = $access['options']['role'] ?? [];
                // Check if 'authenticated' is selected (key or value depending on structure)
                if (in_array('authenticated', $roles) || isset($roles['authenticated'])) {
                    $results['access_restricted'] = true;
                }
            }
            
            // Check Format (Grid)
            $style = $display->getOption('style');
            if (isset($style['type']) && ($style['type'] == 'grid' || $style['type'] == 'views_bootstrap_grid')) {
                $results['grid_format'] = true;
            }
            
            // Check Filters (Taxonomy)
            // This is complex, just checking if ANY filter references taxonomy or product category
            $filters = $display->getOption('filters');
            foreach ($filters as $filter) {
                if (strpos($filter['id'], 'field_product_categories') !== false || 
                    strpos($filter['id'], 'tid') !== false) {
                    $results['filter_correct'] = true; 
                    break;
                }
            }
            
            break 2; // Found the view, stop searching
        }
    }
}

echo json_encode($results);
PHPEOF

# Execute the PHP script via Drush
cd /var/www/html/drupal
VIEW_RESULT_JSON=$($DRUSH php:script /tmp/inspect_view.php 2>/dev/null)

# Clean up PHP script
rm /tmp/inspect_view.php

# 4. Functional Test (Anonymous Access)
# Should return 403 Forbidden
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost/vip-products)
ANON_ACCESS_DENIED="false"
if [ "$HTTP_CODE" == "403" ]; then
    ANON_ACCESS_DENIED="true"
fi

echo "Functional Check: /vip-products returned HTTP $HTTP_CODE (Expected 403)"

# Assemble final JSON
# Default values if PHP script failed
VIEW_FOUND="false"
PATH_CORRECT="false"
ACCESS_RESTRICTED="false"
GRID_FORMAT="false"
FILTER_CORRECT="false"

if [ -n "$VIEW_RESULT_JSON" ]; then
    # Parse values from JSON output using python
    VIEW_FOUND=$(echo "$VIEW_RESULT_JSON" | python3 -c "import sys, json; print(str(json.load(sys.stdin).get('view_found', False)).lower())")
    PATH_CORRECT=$(echo "$VIEW_RESULT_JSON" | python3 -c "import sys, json; print(str(json.load(sys.stdin).get('path_correct', False)).lower())")
    ACCESS_RESTRICTED=$(echo "$VIEW_RESULT_JSON" | python3 -c "import sys, json; print(str(json.load(sys.stdin).get('access_restricted', False)).lower())")
    GRID_FORMAT=$(echo "$VIEW_RESULT_JSON" | python3 -c "import sys, json; print(str(json.load(sys.stdin).get('grid_format', False)).lower())")
    FILTER_CORRECT=$(echo "$VIEW_RESULT_JSON" | python3 -c "import sys, json; print(str(json.load(sys.stdin).get('filter_correct', False)).lower())")
fi

create_result_json /tmp/task_result.json \
    "term_exists=$TERM_EXISTS" \
    "sony_tagged=$SONY_TAGGED" \
    "logi_tagged=$LOGI_TAGGED" \
    "view_found=$VIEW_FOUND" \
    "path_correct=$PATH_CORRECT" \
    "access_restricted=$ACCESS_RESTRICTED" \
    "grid_format=$GRID_FORMAT" \
    "filter_correct=$FILTER_CORRECT" \
    "anon_access_denied=$ANON_ACCESS_DENIED" \
    "http_code=$HTTP_CODE"

chmod 666 /tmp/task_result.json 2>/dev/null || true
cat /tmp/task_result.json
echo "=== Export Complete ==="