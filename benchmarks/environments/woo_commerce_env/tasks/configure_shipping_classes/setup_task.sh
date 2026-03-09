#!/bin/bash
# Setup script for Configure Shipping Classes task

echo "=== Setting up Configure Shipping Classes Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure WordPress/WooCommerce is responsive
if ! check_db_connection; then
    echo "ERROR: Database not accessible"
    exit 1
fi

# 2. Setup "Domestic" Shipping Zone and Flat Rate Method
echo "Configuring initial shipping zone state..."

# Check/Create Domestic Zone
ZONE_ID=$(wc_query "SELECT zone_id FROM wp_woocommerce_shipping_zones WHERE zone_name='Domestic' LIMIT 1")
if [ -z "$ZONE_ID" ]; then
    echo "Creating Domestic shipping zone..."
    # Insert zone
    wc_query "INSERT INTO wp_woocommerce_shipping_zones (zone_name, zone_order) VALUES ('Domestic', 0)"
    ZONE_ID=$(wc_query "SELECT zone_id FROM wp_woocommerce_shipping_zones WHERE zone_name='Domestic' LIMIT 1")
    # Add US location
    wc_query "INSERT INTO wp_woocommerce_shipping_zone_locations (zone_id, location_code, location_type) VALUES ($ZONE_ID, 'US', 'country')"
else
    echo "Domestic zone exists (ID: $ZONE_ID)"
fi

# Check/Create Flat Rate Method in Zone
METHOD_INSTANCE_ID=$(wc_query "SELECT instance_id FROM wp_woocommerce_shipping_zone_methods WHERE zone_id=$ZONE_ID AND method_id='flat_rate' LIMIT 1")
if [ -z "$METHOD_INSTANCE_ID" ]; then
    echo "Adding Flat Rate method to Domestic zone..."
    wc_query "INSERT INTO wp_woocommerce_shipping_zone_methods (zone_id, method_id, method_order, is_enabled) VALUES ($ZONE_ID, 'flat_rate', 1, 1)"
    METHOD_INSTANCE_ID=$(wc_query "SELECT instance_id FROM wp_woocommerce_shipping_zone_methods WHERE zone_id=$ZONE_ID AND method_id='flat_rate' LIMIT 1")
else
    echo "Flat Rate method exists (Instance ID: $METHOD_INSTANCE_ID)"
fi

# Reset Flat Rate Settings to baseline (Cost: 5.00, no class costs)
# Note: WooCommerce stores settings in wp_options as 'woocommerce_flat_rate_{instance_id}_settings'
OPTION_NAME="woocommerce_flat_rate_${METHOD_INSTANCE_ID}_settings"
# Initialize with basic settings
wp option update "$OPTION_NAME" '{"title":"Flat rate","tax_status":"taxable","cost":"5.00"}' --format=json --allow-root

# Save Instance ID for export script
echo "$METHOD_INSTANCE_ID" > /tmp/shipping_method_instance_id.txt

# 3. Ensure Target Products Exist
echo "Verifying target products..."
PROD1=$(get_product_by_sku "WBH-001")
PROD2=$(get_product_by_sku "MWS-GRY-L")

if [ -z "$PROD1" ] || [ -z "$PROD2" ]; then
    echo "ERROR: Target products not found. Re-seeding..."
    # Fallback seeding if missing
    wp wc product create --name="Wireless Bluetooth Headphones" --sku="WBH-001" --regular_price="79.99" --type="simple" --user=admin --allow-root >/dev/null
    wp wc product create --name="Merino Wool Sweater" --sku="MWS-GRY-L" --regular_price="89.99" --type="simple" --user=admin --allow-root >/dev/null
fi

# 4. Record Initial State (Max Term ID) for Anti-Gaming
# We want to verify new terms (shipping classes) are created *after* this point
MAX_TERM_ID=$(wc_query "SELECT MAX(term_id) FROM wp_terms")
echo "${MAX_TERM_ID:-0}" > /tmp/initial_max_term_id.txt
date +%s > /tmp/task_start_time.txt

# 5. Launch Browser
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page"
    exit 1
fi

# Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Method Instance ID: $METHOD_INSTANCE_ID"
echo "Initial Max Term ID: ${MAX_TERM_ID:-0}"