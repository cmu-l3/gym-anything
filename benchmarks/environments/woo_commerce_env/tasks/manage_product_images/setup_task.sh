#!/bin/bash
# Setup script for Manage Product Images task

echo "=== Setting up Manage Product Images Task ==="
set -e

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Ensure WordPress/WooCommerce is running and accessible
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi

# 3. Focus Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 4. Prepare Target Product (Reset State)
echo "Resetting product state for SKU: WBH-001..."
# Find product ID
PRODUCT_ID=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='WBH-001' LIMIT 1")

if [ -z "$PRODUCT_ID" ]; then
    echo "Product not found, creating it..."
    # Create product if missing
    cd /var/www/html/wordpress
    sudo -u www-data wp wc product create \
        --name="Wireless Bluetooth Headphones" \
        --sku="WBH-001" \
        --regular_price="79.99" \
        --type="simple" \
        --status="publish" \
        --path="/var/www/html/wordpress" > /dev/null
    
    PRODUCT_ID=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='WBH-001' LIMIT 1")
fi

# Clear existing images to ensure clean state
if [ -n "$PRODUCT_ID" ]; then
    echo "Clearing images for product ID: $PRODUCT_ID"
    wc_query "DELETE FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key IN ('_thumbnail_id', '_product_image_gallery')"
fi

# 5. Download Real Image Assets
echo "Preparing image assets..."
ASSETS_DIR="/home/ga/Documents/ProductPhotos"
mkdir -p "$ASSETS_DIR"

# Download high-quality unsplash images (using curl -L to follow redirects)
if [ ! -f "$ASSETS_DIR/headphones_main.jpg" ]; then
    curl -L -s -o "$ASSETS_DIR/headphones_main.jpg" "https://images.unsplash.com/photo-1505740420928-5e560c06d30e?q=80&w=1000&auto=format&fit=crop"
fi

if [ ! -f "$ASSETS_DIR/headphones_lifestyle.jpg" ]; then
    curl -L -s -o "$ASSETS_DIR/headphones_lifestyle.jpg" "https://images.unsplash.com/photo-1583394838336-acd977736f90?q=80&w=1000&auto=format&fit=crop"
fi

# Set permissions so the 'ga' user can access them in file picker
chown -R ga:ga "$ASSETS_DIR"

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Product ID: $PRODUCT_ID"
echo "Assets located in: $ASSETS_DIR"