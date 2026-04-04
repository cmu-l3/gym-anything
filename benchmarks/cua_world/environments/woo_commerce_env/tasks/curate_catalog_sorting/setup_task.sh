#!/bin/bash
# Setup script for Curate Catalog Sorting task

echo "=== Setting up Curate Catalog Sorting Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Reset catalog sorting to default state (all 0)
echo "Resetting menu_order for all products to 0..."
wc_query "UPDATE wp_posts SET menu_order = 0 WHERE post_type = 'product';"

# 3. Verify target products exist
SWEATER_ID=$(get_product_by_name "Merino Wool Sweater" | cut -f1)
JEANS_ID=$(get_product_by_name "Slim Fit Denim Jeans" | cut -f1)

if [ -z "$SWEATER_ID" ] || [ -z "$JEANS_ID" ]; then
    echo "ERROR: Required products not found. Seeding them..."
    # Seed if missing (fallback mechanism)
    wp wc product create --name="Merino Wool Sweater" --regular_price="89.99" --user=admin --allow-root > /dev/null
    wp wc product create --name="Slim Fit Denim Jeans" --regular_price="59.99" --user=admin --allow-root > /dev/null
    
    # Refresh IDs
    SWEATER_ID=$(get_product_by_name "Merino Wool Sweater" | cut -f1)
    JEANS_ID=$(get_product_by_name "Slim Fit Denim Jeans" | cut -f1)
fi

echo "Target Products: Sweater (ID: $SWEATER_ID), Jeans (ID: $JEANS_ID)"

# 4. Ensure WordPress admin page is showing
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi

# 5. Focus and maximize Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="