#!/bin/bash
set -e
echo "=== Setting up Flag Low Stock Items task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Start timer
date +%s > /tmp/task_start_time.txt

# 2. DATA PREPARATION
echo "Configuring product stock levels..."

# Helper to set stock for a product by title
# Args: $1=Title, $2=StockQty
configure_product_stock() {
    local title="$1"
    local qty="$2"
    
    # Get Product ID
    local id=$(wc_query "SELECT ID FROM wp_posts WHERE post_title='$title' AND post_type='product' LIMIT 1")
    
    if [ -n "$id" ]; then
        echo "  Setting '$title' (ID: $id) to stock: $qty"
        # Enable stock management
        wc_query "UPDATE wp_postmeta SET meta_value='yes' WHERE post_id=$id AND meta_key='_manage_stock'"
        if [ $? -ne 0 ]; then
            wc_query "INSERT INTO wp_postmeta (post_id, meta_key, meta_value) VALUES ($id, '_manage_stock', 'yes')"
        fi
        
        # Set stock quantity
        wc_query "UPDATE wp_postmeta SET meta_value='$qty' WHERE post_id=$id AND meta_key='_stock'"
        if [ $? -ne 0 ]; then
            wc_query "INSERT INTO wp_postmeta (post_id, meta_key, meta_value) VALUES ($id, '_stock', '$qty')"
        fi
        
        # Set stock status
        local status="instock"
        if [ "$qty" -le "0" ]; then status="outofstock"; fi
        wc_query "UPDATE wp_postmeta SET meta_value='$status' WHERE post_id=$id AND meta_key='_stock_status'"
    else
        echo "  WARNING: Product '$title' not found."
    fi
}

# Ensure targets exist and have correct stock
configure_product_stock "Beanie" 4
configure_product_stock "Cap" 8
configure_product_stock "Belt" 2
configure_product_stock "Sunglasses" 15
configure_product_stock "Long Sleeve Tee" 25

# 3. CLEANUP: Remove 'Urgent Reorder' tag if it exists to ensure agent creates/applies it fresh
echo "Cleaning up tags..."
TAG_ID=$(wc_query "SELECT term_id FROM wp_terms WHERE name='Urgent Reorder' LIMIT 1")
if [ -n "$TAG_ID" ]; then
    echo "  Removing existing 'Urgent Reorder' tag (ID: $TAG_ID)..."
    # Remove relationships
    TERM_TAX_ID=$(wc_query "SELECT term_taxonomy_id FROM wp_term_taxonomy WHERE term_id=$TAG_ID")
    if [ -n "$TERM_TAX_ID" ]; then
        wc_query "DELETE FROM wp_term_relationships WHERE term_taxonomy_id=$TERM_TAX_ID"
        wc_query "DELETE FROM wp_term_taxonomy WHERE term_taxonomy_id=$TERM_TAX_ID"
    fi
    wc_query "DELETE FROM wp_terms WHERE term_id=$TAG_ID"
fi

# 4. BROWSER SETUP
echo "Launching Firefox..."
# Check if Firefox is running
if ! pgrep -f "firefox" > /dev/null; then
    # Start Firefox opening the Products page directly
    su - ga -c "DISPLAY=:1 firefox http://localhost/wp-admin/edit.php?post_type=product &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "firefox" > /dev/null; then
            break
        fi
        sleep 1
    done
else
    # Navigate existing Firefox
    su - ga -c "DISPLAY=:1 firefox -new-tab http://localhost/wp-admin/edit.php?post_type=product &"
fi

# Maximize
sleep 2
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Wait for page load
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="