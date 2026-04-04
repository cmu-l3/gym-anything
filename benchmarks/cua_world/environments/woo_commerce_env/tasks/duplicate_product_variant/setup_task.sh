#!/bin/bash
# Setup script for Duplicate Product Variant task

echo "=== Setting up Duplicate Product Variant Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify source product exists and record its ID
echo "Verifying source product..."
SOURCE_DATA=$(get_product_by_sku "WBH-001" 2>/dev/null)

if [ -z "$SOURCE_DATA" ]; then
    echo "ERROR: Source product WBH-001 not found. Attempting to recreate..."
    # Fallback: Create the source product if missing (sanity check)
    wp wc product create --name="Wireless Bluetooth Headphones" --sku="WBH-001" --regular_price="79.99" --type="simple" --status="publish" --description="Premium wireless Bluetooth headphones with active noise cancellation, 30-hour battery life, and comfortable over-ear design." --short_description="Premium wireless headphones with ANC" --user=admin --allow-root > /dev/null 2>&1
    SOURCE_DATA=$(get_product_by_sku "WBH-001" 2>/dev/null)
fi

if [ -n "$SOURCE_DATA" ]; then
    SOURCE_ID=$(echo "$SOURCE_DATA" | cut -f1)
    echo "$SOURCE_ID" > /tmp/source_product_id.txt
    
    # Record source description for comparison later (to verify duplication)
    wc_query "SELECT post_content FROM wp_posts WHERE ID=$SOURCE_ID" > /tmp/source_description.txt
    echo "Source product verified: ID $SOURCE_ID"
else
    echo "FATAL: Could not establish source product."
    exit 1
fi

# CRITICAL: Ensure WordPress admin page is showing
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Navigate explicitly to "All Products" to assist agent start state
su - ga -c "DISPLAY=:1 firefox http://localhost/wp-admin/edit.php?post_type=product &"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="