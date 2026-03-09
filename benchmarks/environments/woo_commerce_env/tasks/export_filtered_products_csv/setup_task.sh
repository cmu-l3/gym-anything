#!/bin/bash
# Setup script for Export Filtered Products CSV task

echo "=== Setting up Export Filtered Products CSV Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous attempts or downloads
rm -f /home/ga/Documents/clothing_prices.csv
rm -f /home/ga/Downloads/wc-product-export*.csv
mkdir -p /home/ga/Documents

# 2. Ensure Database is ready
if ! check_db_connection; then
    echo "Waiting for database..."
    sleep 5
fi

# 3. Ensure 'Clothing' category exists and has data
# We'll rely on the standard environment data, but verify it here.
echo "Verifying 'Clothing' category data..."
CLOTHING_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_term_relationships tr 
    JOIN wp_term_taxonomy tt ON tr.term_taxonomy_id = tt.term_taxonomy_id 
    JOIN wp_terms t ON tt.term_id = t.term_id 
    WHERE t.name = 'Clothing' AND tt.taxonomy = 'product_cat'")

echo "Found $CLOTHING_COUNT products in Clothing category."

if [ "$CLOTHING_COUNT" -eq "0" ]; then
    echo "Seeding backup Clothing data..."
    # Fallback seeding if env is empty
    wp wc product_cat create --name="Clothing" --user=admin --allow-root || true
    wp wc product create --name="Basic White Tee" --sku="TEE-WHT-001" --regular_price="19.99" --categories='[{"id": "Clothing"}]' --user=admin --allow-root
    wp wc product create --name="Blue Jeans" --sku="JNS-BLU-001" --regular_price="49.99" --categories='[{"id": "Clothing"}]' --user=admin --allow-root
fi

# 4. Ensure Firefox is open to the Products page
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi

# Navigate specifically to the Products page if not there
# We use xdotool to force navigation to ensure consistent starting state
echo "Navigating to Products page..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # CTRL+L to focus address bar, type url, enter
    DISPLAY=:1 xdotool key ctrl+l
    sleep 0.5
    DISPLAY=:1 xdotool type "http://localhost/wp-admin/edit.php?post_type=product"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 5
fi

# Maximize window
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Capture initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="