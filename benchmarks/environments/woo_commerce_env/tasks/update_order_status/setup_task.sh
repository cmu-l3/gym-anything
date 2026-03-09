#!/bin/bash
# Setup script for Update Order Status task

echo "=== Setting up Update Order Status Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure Customer 'Maria Garcia' exists
echo "Checking for customer Maria Garcia..."
CUSTOMER_DATA=$(get_customer_by_name "Maria" "Garcia" 2>/dev/null)

if [ -z "$CUSTOMER_DATA" ]; then
    echo "Creating customer Maria Garcia..."
    # Create via WP-CLI
    wp user create maria.garcia maria.garcia@example.com \
        --role=customer \
        --first_name="Maria" \
        --last_name="Garcia" \
        --user_pass="MariaPass123!" \
        --path=/var/www/html/wordpress \
        --allow-root 2>/dev/null
    
    # Verify creation
    CUSTOMER_DATA=$(get_customer_by_name "Maria" "Garcia" 2>/dev/null)
fi

if [ -z "$CUSTOMER_DATA" ]; then
    echo "FATAL: Failed to create customer Maria Garcia"
    exit 1
fi

CUSTOMER_ID=$(echo "$CUSTOMER_DATA" | cut -f1)
echo "Customer ID: $CUSTOMER_ID"

# 3. Ensure a 'Processing' order exists for this customer
echo "Checking for existing processing orders..."
# Query for orders by this customer with status 'wc-processing'
EXISTING_ORDER=$(wc_query "SELECT p.ID FROM wp_posts p 
    JOIN wp_postmeta pm ON p.ID = pm.post_id 
    WHERE p.post_type='shop_order' 
    AND p.post_status='wc-processing' 
    AND pm.meta_key='_customer_user' 
    AND pm.meta_value='$CUSTOMER_ID' 
    LIMIT 1" 2>/dev/null)

if [ -z "$EXISTING_ORDER" ]; then
    echo "Creating new processing order for Maria Garcia..."
    # Create order via WP-CLI
    ORDER_ID=$(wp wc order create --user=$CUSTOMER_ID --status=processing --path=/var/www/html/wordpress --user=admin --porcelain --allow-root 2>/dev/null)
    
    # Add a product to the order (Wireless Bluetooth Headphones)
    PRODUCT_DATA=$(get_product_by_name "Wireless Bluetooth Headphones" 2>/dev/null)
    if [ -n "$PRODUCT_DATA" ]; then
        PROD_ID=$(echo "$PRODUCT_DATA" | cut -f1)
        wp wc order product add $ORDER_ID $PROD_ID --quantity=1 --path=/var/www/html/wordpress --user=admin --allow-root > /dev/null 2>&1
    else
        echo "WARNING: Product not found, adding generic line item"
    fi
    
    # Calculate totals
    wp wc order update $ORDER_ID --path=/var/www/html/wordpress --user=admin --allow-root > /dev/null 2>&1
else
    ORDER_ID="$EXISTING_ORDER"
    echo "Found existing processing order: $ORDER_ID"
fi

# Record the target order ID for the exporter
echo "$ORDER_ID" > /tmp/target_order_id.txt
echo "Target Order ID: $ORDER_ID"

# 4. Ensure no existing note with the tracking number exists (cleanup)
# This prevents false positives from previous runs
echo "Cleaning up any previous notes with target tracking number..."
wc_query "DELETE FROM wp_comments WHERE comment_post_ID=$ORDER_ID AND comment_content LIKE '%TRACK-2024-78542%'" 2>/dev/null

# 5. Launch Firefox to WordPress Admin
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page"
    exit 1
fi

# Focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="