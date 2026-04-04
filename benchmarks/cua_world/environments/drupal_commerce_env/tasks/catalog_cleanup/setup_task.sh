#!/bin/bash
# Setup script for Catalog Cleanup task
echo "=== Setting up Catalog Cleanup Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure services are running
echo "Ensuring infrastructure services..."
ensure_services_running 90

# 2. Record Task Start Time
date +%s > /tmp/task_start_time.txt

# 3. Record Initial Database State
# We dump the relevant fields for all products to detect changes later
echo "Recording initial catalog state..."
drupal_db_query "
SELECT 
    p.product_id, 
    p.title, 
    p.status as product_status,
    v.variation_id,
    v.sku,
    v.price__number
FROM commerce_product_field_data p
LEFT JOIN commerce_product__variations pv ON p.product_id = pv.entity_id
LEFT JOIN commerce_product_variation_field_data v ON pv.variations_target_id = v.variation_id
ORDER BY p.product_id ASC
" > /tmp/initial_catalog_dump.txt

# Also save as JSON for easier parsing if needed, though raw text comparison is often enough for baseline
# We'll use a python script to structure this for the export script
python3 -c '
import sys, json
lines = sys.stdin.readlines()
products = []
for line in lines:
    parts = line.strip().split("\t")
    if len(parts) >= 6:
        products.append({
            "product_id": parts[0],
            "title": parts[1],
            "status": parts[2],
            "variation_id": parts[3],
            "sku": parts[4],
            "price": parts[5]
        })
print(json.dumps(products))
' < /tmp/initial_catalog_dump.txt > /tmp/initial_catalog_state.json

chmod 666 /tmp/initial_catalog_state.json

# 4. Navigate Firefox to Product List
echo "Navigating to Product List..."
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

navigate_firefox_to "http://localhost/admin/commerce/products"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_start.png
echo "Setup complete."