#!/bin/bash
# Setup script for Customize Shop Layout task

echo "=== Setting up Customize Shop Layout Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# ============================================================
# RESET STATE TO KNOWN DEFAULTS
# ============================================================
# We explicitly set values to ensure the agent has to change them.
# Default state: Products only, Default sorting, 4x4 grid.

echo "Resetting WooCommerce catalog options to defaults..."

# 1. Shop page display: '' means products only (default)
wp option update woocommerce_shop_page_display "" --allow-root > /dev/null

# 2. Default sorting: 'menu_order' (default sorting + custom ordering)
wp option update woocommerce_default_catalog_orderby "menu_order" --allow-root > /dev/null

# 3. Grid columns: 4
wp option update woocommerce_catalog_columns "4" --allow-root > /dev/null

# 4. Grid rows: 4
wp option update woocommerce_catalog_rows "4" --allow-root > /dev/null

# Record initial values for verification logic (to detect "no change")
echo "4" > /tmp/initial_columns.txt
echo "4" > /tmp/initial_rows.txt

# ============================================================
# ENSURE ENVIRONMENT IS READY
# ============================================================

# CRITICAL: Ensure WordPress admin page is showing
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi
echo "WordPress admin page confirmed loaded"

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
echo "Initial screenshot saved"

echo "=== Customize Shop Layout Task Setup Complete ==="
echo "Agent should be on the WP Admin Dashboard."