#!/bin/bash
# Setup script for Add Coupon task

echo "=== Setting up Add Coupon Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record initial coupon count for verification
echo "Recording initial coupon count..."
INITIAL_COUNT=$(get_coupon_count 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_coupon_count
echo "Initial coupon count: $INITIAL_COUNT"

# CRITICAL: Ensure WordPress admin page is showing (not blank Firefox tab)
# This uses the robust ensure_wordpress_shown function that checks window title
# for WordPress-specific text, not just "Firefox" or "Mozilla Firefox"
# MUST exit with failure if WordPress doesn't load - do NOT continue with blank browser
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

# Take initial screenshot (should show WordPress admin, NOT blank tab)
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved - verify it shows WordPress admin"

echo "=== Add Coupon Task Setup Complete ==="
echo "Agent should be on the WooCommerce admin dashboard (already logged in)."
