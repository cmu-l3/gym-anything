#!/bin/bash
# Setup script for Configure Exclusive Product task

echo "=== Setting up Configure Exclusive Product Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Identify Target Product
PRODUCT_NAME="Wireless Bluetooth Headphones"
PRODUCT_DATA=$(get_product_by_name "$PRODUCT_NAME" 2>/dev/null)

if [ -z "$PRODUCT_DATA" ]; then
    echo "Target product not found. Creating it..."
    wp wc product create --name="$PRODUCT_NAME" --sku="WBH-001" --regular_price="79.99" --type="simple" --status="publish" --description="Premium headphones." --short_description="Great sound." --user=admin --allow-root > /dev/null
    PRODUCT_DATA=$(get_product_by_name "$PRODUCT_NAME" 2>/dev/null)
fi

PID=$(echo "$PRODUCT_DATA" | cut -f1)
echo "Target Product ID: $PID"
echo "$PID" > /tmp/target_product_id.txt

# 2. Reset Product State to "Standard"
# Ensure it is visible in catalog and search (remove visibility terms)
echo "Resetting visibility..."
wp wc product update "$PID" --catalog_visibility="visible" --user=admin --allow-root > /dev/null

# Ensure "Sold individually" is NO
echo "Resetting inventory settings..."
wp post meta update "$PID" _sold_individually "no" --allow-root > /dev/null

# Reset Short Description (remove the warning text if it exists from previous run)
echo "Resetting short description..."
CURRENT_DESC=$(wp post get "$PID" --field=post_excerpt --allow-root)
CLEAN_DESC=${CURRENT_DESC//\*\*\* LIMIT 1 PER CUSTOMER \*\*\*/}
wp post update "$PID" --post_excerpt="$CLEAN_DESC" --allow-root > /dev/null

# 3. Ensure WordPress admin is loaded in Firefox
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# 4. Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="