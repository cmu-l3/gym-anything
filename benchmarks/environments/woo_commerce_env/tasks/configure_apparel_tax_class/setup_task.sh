#!/bin/bash
# Setup script for Configure Apparel Tax Class task

echo "=== Setting up Configure Apparel Tax Class Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Tax Calculation is ENABLED
echo "Enabling tax calculation..."
wp option update woocommerce_calc_taxes "yes" --allow-root 2>/dev/null

# 2. Ensure target product exists
TARGET_PRODUCT="Organic Cotton T-Shirt"
PRODUCT_DATA=$(get_product_by_name "$TARGET_PRODUCT" 2>/dev/null)

if [ -z "$PRODUCT_DATA" ]; then
    echo "Creating target product '$TARGET_PRODUCT'..."
    wp wc product create --name="$TARGET_PRODUCT" --type="simple" --regular_price="24.99" --status="publish" --user=admin --allow-root 2>/dev/null
    PRODUCT_DATA=$(get_product_by_name "$TARGET_PRODUCT" 2>/dev/null)
fi

# Record Product ID for export script
if [ -n "$PRODUCT_DATA" ]; then
    PRODUCT_ID=$(echo "$PRODUCT_DATA" | cut -f1)
    echo "$PRODUCT_ID" > /tmp/target_product_id.txt
    echo "Target Product ID: $PRODUCT_ID"
else
    echo "ERROR: Could not create/find target product."
    exit 1
fi

# 3. Record initial tax classes (to check preservation)
INITIAL_TAX_CLASSES=$(wp option get woocommerce_tax_classes --allow-root 2>/dev/null)
echo "$INITIAL_TAX_CLASSES" > /tmp/initial_tax_classes.txt
echo "Initial Tax Classes: $(cat /tmp/initial_tax_classes.txt)"

# 4. Ensure WordPress admin is displayed
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page."
    exit 1
fi

# 5. Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="