#!/bin/bash
# Setup script for Configure Terms Page task

echo "=== Setting up Configure Terms Page Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp for anti-gaming (to ensure page is created NOW)
date +%s > /tmp/task_start_time.txt

# Record initial value of the terms page setting
INITIAL_TERMS_ID=$(wc_query "SELECT option_value FROM wp_options WHERE option_name = 'woocommerce_terms_page_id'" 2>/dev/null)
echo "${INITIAL_TERMS_ID:-0}" > /tmp/initial_terms_id.txt
echo "Initial Terms Page ID: ${INITIAL_TERMS_ID:-0}"

# CRITICAL: Ensure WordPress admin page is showing (not blank Firefox tab)
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    echo "Window title check failed. Firefox may show blank tab instead of WooCommerce."
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

echo "=== Setup Complete ==="
echo "Agent should create a page and configure it in WooCommerce settings."