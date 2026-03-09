#!/bin/bash
# Setup script for Grant Manual Download Access task

echo "=== Setting up Grant Manual Download Access Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial counts for verification
echo "Recording initial state..."
INITIAL_ORDER_COUNT=$(get_order_count 2>/dev/null || echo "0")
echo "$INITIAL_ORDER_COUNT" > /tmp/initial_order_count
INITIAL_PRODUCT_COUNT=$(get_product_count 2>/dev/null || echo "0")
echo "$INITIAL_PRODUCT_COUNT" > /tmp/initial_product_count

# Record task start time
date +%s > /tmp/task_start_time.txt

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

echo "=== Setup Complete ==="