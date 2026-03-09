#!/bin/bash
# Setup script for Configure Product Attributes task

echo "=== Setting up Configure Product Attributes Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. CLEANUP: Remove existing attributes if they exist (to ensure fresh start)
echo "Checking for existing attributes to clean up..."
# Delete attributes via WP-CLI to ensure clean state
wp wc product_attribute delete $(wp wc product_attribute list --format=ids --user=admin) --force --user=admin --allow-root 2>/dev/null || true

# 2. VERIFY PRODUCTS: Ensure target products exist
echo "Verifying target products exist..."
P1=$(get_product_by_sku "OCT-BLK-M" 2>/dev/null)
P2=$(get_product_by_sku "SFDJ-BLU-32" 2>/dev/null)
P3=$(get_product_by_sku "MWS-GRY-L" 2>/dev/null)

if [ -z "$P1" ] || [ -z "$P2" ] || [ -z "$P3" ]; then
    echo "FATAL: One or more required products (T-Shirt, Jeans, Sweater) are missing from the environment."
    exit 1
fi
echo "All target products found."

# 3. SETUP BROWSER: Ensure WordPress admin is shown
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