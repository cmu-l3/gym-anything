#!/bin/bash
# Setup script for Configure Webhook task

echo "=== Setting up Configure Webhook Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Record initial webhook count
echo "Recording initial webhook count..."
INITIAL_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_wc_webhooks" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_webhook_count.txt
echo "Initial webhook count: $INITIAL_COUNT"

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
echo "Initial screenshot saved"

echo "=== Configure Webhook Task Setup Complete ==="
echo "Agent should navigate to WooCommerce > Settings > Advanced > Webhooks."