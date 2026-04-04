#!/bin/bash
# Setup script for Add Product Reviews task

echo "=== Setting up Add Product Reviews Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial comment/review count for verification
echo "Recording initial review count..."
INITIAL_REVIEWS=$(wc_query "SELECT COUNT(*) FROM wp_comments WHERE comment_type='review' OR (comment_type='' AND comment_post_ID IN (SELECT ID FROM wp_posts WHERE post_type='product'))" 2>/dev/null || echo "0")
echo "$INITIAL_REVIEWS" > /tmp/initial_review_count.txt
echo "Initial review count: $INITIAL_REVIEWS"

# Ensure target products exist
echo "Verifying target products..."
HEADPHONES=$(get_product_by_sku "WBH-001")
TSHIRT=$(get_product_by_sku "OCT-BLK-M")

if [ -z "$HEADPHONES" ]; then
    echo "Creating missing product: Wireless Bluetooth Headphones..."
    wp wc product create --name="Wireless Bluetooth Headphones" --sku="WBH-001" --regular_price="79.99" --type="simple" --status="publish" --description="Premium wireless Bluetooth headphones." --user=admin --allow-root > /dev/null
fi

if [ -z "$TSHIRT" ]; then
    echo "Creating missing product: Organic Cotton T-Shirt..."
    wp wc product create --name="Organic Cotton T-Shirt" --sku="OCT-BLK-M" --regular_price="24.99" --type="simple" --status="publish" --description="Soft organic cotton t-shirt." --user=admin --allow-root > /dev/null
fi

# Reset review settings to a known bad state (so agent actually has to change them)
echo "Resetting review settings..."
wp option update woocommerce_enable_reviews "no" --allow-root > /dev/null
wp option update woocommerce_enable_review_rating "no" --allow-root > /dev/null
wp option update woocommerce_review_rating_required "no" --allow-root > /dev/null

# CRITICAL: Ensure WordPress admin page is showing
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
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

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="