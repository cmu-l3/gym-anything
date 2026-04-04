#!/bin/bash
# Setup script for Generate API Keys task

echo "=== Setting up Generate API Keys Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous attempts
echo "Cleaning up previous state..."
rm -f /home/ga/api_credentials.txt
# Remove any existing keys with the target description to ensure clean state
wc_query "DELETE FROM wp_woocommerce_api_keys WHERE description = 'ShipStation Integration'" 2>/dev/null

# Record initial API key count for verification
echo "Recording initial API key count..."
INITIAL_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_woocommerce_api_keys" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_key_count
echo "Initial key count: $INITIAL_COUNT"

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

echo "=== Setup Complete ==="