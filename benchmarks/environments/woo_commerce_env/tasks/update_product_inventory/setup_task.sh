#!/bin/bash
# Setup script for Update Product Inventory task
set -e

echo "=== Setting up Update Product Inventory Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Check database connectivity
if ! check_db_connection; then
    echo "ERROR: Database connection failed."
    exit 1
fi

# ==============================================================================
# 1. Identify Target Products and Record Initial State
# ==============================================================================
echo "identifying target products..."

# Get Product IDs
WBH_ID=$(get_product_by_sku "WBH-001" | cut -f1)
USBC_ID=$(get_product_by_sku "USBC-065" | cut -f1)
SFDJ_ID=$(get_product_by_sku "SFDJ-BLU-32" | cut -f1)

if [ -z "$WBH_ID" ] || [ -z "$USBC_ID" ] || [ -z "$SFDJ_ID" ]; then
    echo "ERROR: One or more target products not found!"
    exit 1
fi

echo "Found products: WBH=$WBH_ID, USBC=$USBC_ID, SFDJ=$SFDJ_ID"

# Ensure stock management is enabled for these products
# (If not enabled, the stock quantity field might be hidden/disabled in UI)
echo "Ensuring stock management is enabled..."
for PID in "$WBH_ID" "$USBC_ID" "$SFDJ_ID"; do
    wc_query "UPDATE wp_postmeta SET meta_value='yes' WHERE post_id=$PID AND meta_key='_manage_stock'"
    # If key didn't exist, insert it
    EXISTS=$(wc_query "SELECT COUNT(*) FROM wp_postmeta WHERE post_id=$PID AND meta_key='_manage_stock'")
    if [ "$EXISTS" = "0" ]; then
        wc_query "INSERT INTO wp_postmeta (post_id, meta_key, meta_value) VALUES ($PID, '_manage_stock', 'yes')"
    fi
done

# Reset specific fields to ensure agent must change them (avoid accidental correct state)
# 1. Reset Headphones low stock
wc_query "UPDATE wp_postmeta SET meta_value='0' WHERE post_id=$WBH_ID AND meta_key='_low_stock_amount'"
# 2. Reset Jeans backorders to 'no'
wc_query "UPDATE wp_postmeta SET meta_value='no' WHERE post_id=$SFDJ_ID AND meta_key='_backorders'"
# 3. Ensure stock values are NOT the target values
current_wbh_stock=$(get_product_stock "$WBH_ID")
if [ "$current_wbh_stock" == "275" ]; then
    wc_query "UPDATE wp_postmeta SET meta_value='100' WHERE post_id=$WBH_ID AND meta_key='_stock'"
fi

# Record initial state for anti-gaming verification
cat > /tmp/initial_inventory.json << EOF
{
  "WBH-001": {
    "id": "$WBH_ID",
    "stock": "$(get_product_stock $WBH_ID)",
    "low_stock": "$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$WBH_ID AND meta_key='_low_stock_amount' LIMIT 1")"
  },
  "USBC-065": {
    "id": "$USBC_ID",
    "stock": "$(get_product_stock $USBC_ID)"
  },
  "SFDJ-BLU-32": {
    "id": "$SFDJ_ID",
    "stock": "$(get_product_stock $SFDJ_ID)",
    "backorders": "$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$SFDJ_ID AND meta_key='_backorders' LIMIT 1")"
  }
}
EOF

# ==============================================================================
# 2. Prepare Application State (Firefox)
# ==============================================================================

# Ensure WordPress is ready
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# Launch Firefox specifically to the Products page to save agent one click
echo "Navigating to Products list..."
su - ga -c "DISPLAY=:1 firefox --new-tab 'http://localhost/wp-admin/edit.php?post_type=product' &"
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="