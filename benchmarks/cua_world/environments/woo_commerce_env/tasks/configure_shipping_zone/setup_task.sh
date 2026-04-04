#!/bin/bash
# Setup script for Configure Shipping Zone task
set -e

echo "=== Setting up Configure Shipping Zone Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify database connectivity
if ! check_db_connection; then
    echo "ERROR: Cannot connect to database. Aborting setup."
    exit 1
fi

# Clean up ANY existing shipping zones to ensure a fresh start
# This prevents ambiguity if a "Continental US" zone already exists
echo "Cleaning existing shipping zones..."
wc_query "DELETE FROM wp_woocommerce_shipping_zone_locations" 2>/dev/null || true
wc_query "DELETE FROM wp_woocommerce_shipping_zone_methods" 2>/dev/null || true
wc_query "DELETE FROM wp_woocommerce_shipping_zones" 2>/dev/null || true
# Clean up flat rate settings options to ensure no stale data
wc_query "DELETE FROM wp_options WHERE option_name LIKE 'woocommerce_flat_rate_%_settings'" 2>/dev/null || true

# Record initial zone count (should be 0)
INITIAL_COUNT=$(wc_query "SELECT COUNT(*) FROM wp_woocommerce_shipping_zones" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_zone_count.txt
echo "Initial shipping zone count: $INITIAL_COUNT"

# Ensure WordPress is accessible
echo "Ensuring WordPress is accessible..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress - task cannot proceed"
    exit 1
fi

# Kill any existing Firefox instances
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox directly to the Shipping Settings page
# The agent starts right where they need to be
echo "Launching Firefox to Shipping Settings..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/admin.php?page=wc-settings&tab=shipping' &"

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i -E "firefox|mozilla|shipping|woocommerce"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done
sleep 5

# Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Dismiss any potential admin notices or popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="