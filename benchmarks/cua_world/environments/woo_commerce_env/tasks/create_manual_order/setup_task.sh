#!/bin/bash
# Setup script for Create Manual Order task

echo "=== Setting up Create Manual Order Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record Start Time
date +%s > /tmp/task_start_time.txt

# 2. Record Initial Order Count
echo "Recording initial order count..."
INITIAL_COUNT=$(get_order_count 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_order_count
echo "Initial order count: $INITIAL_COUNT"

# 3. Ensure Payment Gateway (COD) is enabled
# This is critical so the agent can select it
echo "Ensuring Cash on Delivery is enabled..."
wp option update woocommerce_cod_settings '{"enabled":"yes","title":"Cash on delivery","description":"Pay with cash upon delivery.","instructions":"Pay with cash upon delivery.","enable_for_methods":[],"enable_for_virtual":"yes"}' --format=json --allow-root 2>/dev/null || true

# 4. Verify Products Exist
echo "Verifying required products..."
P1=$(get_product_by_sku "WBH-001")
P2=$(get_product_by_sku "USBC-065")

if [ -z "$P1" ] || [ -z "$P2" ]; then
    echo "ERROR: Required products (WBH-001 or USBC-065) missing from environment."
    # Attempt to seed them if missing (fail-safe)
    wp wc product create --name="Wireless Bluetooth Headphones" --sku="WBH-001" --regular_price="79.99" --type="simple" --user=admin --allow-root >/dev/null 2>&1 || true
    wp wc product create --name="USB-C Laptop Charger 65W" --sku="USBC-065" --regular_price="34.99" --type="simple" --user=admin --allow-root >/dev/null 2>&1 || true
fi

# 5. Ensure WordPress Admin is accessible
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# 6. Focus and Maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 7. Initial Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="