#!/bin/bash
# Setup script for Create Refurbished Product task

echo "=== Setting up Create Refurbished Product Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure source product exists
SOURCE_SKU="WBH-001"
SOURCE_PRODUCT=$(get_product_by_sku "$SOURCE_SKU" 2>/dev/null)

if [ -z "$SOURCE_PRODUCT" ]; then
    echo "Creating source product..."
    wp wc product create --name="Wireless Bluetooth Headphones" \
        --sku="$SOURCE_SKU" \
        --regular_price="79.99" \
        --type="simple" \
        --status="publish" \
        --description="Premium wireless Bluetooth headphones with active noise cancellation, 30-hour battery life, and comfortable over-ear design." \
        --short_description="Premium wireless headphones with ANC" \
        --manage_stock=true \
        --stock_quantity=150 \
        --user=admin \
        --allow-root 2>&1
else
    echo "Source product $SOURCE_SKU already exists."
fi

# Ensure target product does NOT exist (cleanup from previous runs)
TARGET_SKU="WBH-001-REF"
TARGET_PRODUCT=$(get_product_by_sku "$TARGET_SKU" 2>/dev/null)
if [ -n "$TARGET_PRODUCT" ]; then
    TARGET_ID=$(echo "$TARGET_PRODUCT" | cut -f1)
    echo "Removing stale target product (ID: $TARGET_ID)..."
    wp post delete "$TARGET_ID" --force --allow-root 2>&1
fi

# Record initial product count
INITIAL_COUNT=$(get_product_count 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_product_count

# CRITICAL: Ensure WordPress admin page is showing
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi

# Focus and maximize Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="