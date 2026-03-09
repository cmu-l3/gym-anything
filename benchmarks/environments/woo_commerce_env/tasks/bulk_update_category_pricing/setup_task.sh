#!/bin/bash
echo "=== Setting up Bulk Update Category Pricing Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. PREPARE DATA: Reset prices to known integer values for deterministic math
# ==============================================================================
echo "Resetting product prices for consistency..."

# Wait for DB connectivity
if ! check_db_connection; then
    echo "Error: DB not reachable"
    exit 1
fi

# Set specific prices for CLOTHING (Target Group)
# T-Shirt -> 20.00 (Expected +15% -> 23.00)
wc_query "UPDATE wp_postmeta pm 
          JOIN wp_posts p ON pm.post_id = p.ID 
          SET pm.meta_value = '20.00' 
          WHERE p.post_title = 'Organic Cotton T-Shirt' AND pm.meta_key = '_regular_price'"

# Jeans -> 40.00 (Expected +15% -> 46.00)
wc_query "UPDATE wp_postmeta pm 
          JOIN wp_posts p ON pm.post_id = p.ID 
          SET pm.meta_value = '40.00' 
          WHERE p.post_title = 'Slim Fit Denim Jeans' AND pm.meta_key = '_regular_price'"

# Sweater -> 100.00 (Expected +15% -> 115.00)
wc_query "UPDATE wp_postmeta pm 
          JOIN wp_posts p ON pm.post_id = p.ID 
          SET pm.meta_value = '100.00' 
          WHERE p.post_title = 'Merino Wool Sweater' AND pm.meta_key = '_regular_price'"

# Set specific prices for ELECTRONICS (Control Group - Should NOT change)
# Headphones -> 80.00
wc_query "UPDATE wp_postmeta pm 
          JOIN wp_posts p ON pm.post_id = p.ID 
          SET pm.meta_value = '80.00' 
          WHERE p.post_title = 'Wireless Bluetooth Headphones' AND pm.meta_key = '_regular_price'"

# Charger -> 30.00
wc_query "UPDATE wp_postmeta pm 
          JOIN wp_posts p ON pm.post_id = p.ID 
          SET pm.meta_value = '30.00' 
          WHERE p.post_title = 'USB-C Laptop Charger 65W' AND pm.meta_key = '_regular_price'"

# Flush object cache (if applicable) by updating a transient option (hacky but effective for WP)
wc_query "UPDATE wp_options SET option_value = UNIX_TIMESTAMP() WHERE option_name = '_transient_timeout_woocommerce_product_cat_children'"

# ==============================================================================
# 2. CAPTURE INITIAL STATE
# ==============================================================================
echo "Capturing initial price state..."

# Helper to get price by exact name
get_price() {
    local name="$1"
    wc_query "SELECT meta_value FROM wp_postmeta pm JOIN wp_posts p ON pm.post_id = p.ID WHERE p.post_title='$name' AND pm.meta_key='_regular_price' LIMIT 1"
}

cat > /tmp/initial_prices.json << EOF
{
  "clothing": {
    "Organic Cotton T-Shirt": $(get_price "Organic Cotton T-Shirt"),
    "Slim Fit Denim Jeans": $(get_price "Slim Fit Denim Jeans"),
    "Merino Wool Sweater": $(get_price "Merino Wool Sweater")
  },
  "electronics": {
    "Wireless Bluetooth Headphones": $(get_price "Wireless Bluetooth Headphones"),
    "USB-C Laptop Charger 65W": $(get_price "USB-C Laptop Charger 65W")
  }
}
EOF

echo "Initial state saved:"
cat /tmp/initial_prices.json

# ==============================================================================
# 3. SETUP BROWSER
# ==============================================================================

# Ensure WordPress admin is loaded
if ! ensure_wordpress_shown 60; then
    echo "FATAL: WordPress admin not loading."
    exit 1
fi

# Navigate directly to All Products page to save agent time
echo "Navigating to Products page..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/edit.php?post_type=product' &"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="