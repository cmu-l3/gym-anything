#!/bin/bash
# Setup script for Configure Formula Shipping Rate task
set -e
echo "=== Setting up Configure Formula Shipping Rate Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for database
for i in {1..30}; do
    if check_db_connection; then
        break
    fi
    sleep 2
done

# ==============================================================================
# PREPARE SHIPPING ZONES (Clean Slate Approach)
# ==============================================================================
echo "Preparing shipping zones..."

# 1. Delete existing Domestic zone if present (to avoid duplicates/ambiguity)
ZONE_ID=$(wc_query "SELECT zone_id FROM wp_woocommerce_shipping_zones WHERE zone_name='Domestic' LIMIT 1")
if [ -n "$ZONE_ID" ]; then
    echo "Removing existing Domestic zone (ID: $ZONE_ID)..."
    wc_query "DELETE FROM wp_woocommerce_shipping_zones WHERE zone_id=$ZONE_ID"
    wc_query "DELETE FROM wp_woocommerce_shipping_zone_locations WHERE zone_id=$ZONE_ID"
    # Also delete associated methods to keep wp_options clean (optional but good practice)
    METHOD_INSTANCES=$(wc_query "SELECT instance_id FROM wp_woocommerce_shipping_zone_methods WHERE zone_id=$ZONE_ID")
    if [ -n "$METHOD_INSTANCES" ]; then
        wc_query "DELETE FROM wp_woocommerce_shipping_zone_methods WHERE zone_id=$ZONE_ID"
        for INSTANCE in $METHOD_INSTANCES; do
             # Use WP-CLI to delete option cleanly
             wp option delete "woocommerce_flat_rate_${INSTANCE}_settings" --allow-root >/dev/null 2>&1 || true
        done
    fi
fi

# 2. Create "Domestic" zone fresh
echo "Creating Domestic shipping zone..."
wc_query "INSERT INTO wp_woocommerce_shipping_zones (zone_name, zone_order) VALUES ('Domestic', 0)"
NEW_ZONE_ID=$(wc_query "SELECT zone_id FROM wp_woocommerce_shipping_zones WHERE zone_name='Domestic' LIMIT 1")

# 3. Add US location to zone
wc_query "INSERT INTO wp_woocommerce_shipping_zone_locations (zone_id, location_code, location_type) VALUES ($NEW_ZONE_ID, 'US', 'country')"

echo "Created 'Domestic' zone with ID: $NEW_ZONE_ID"
echo "$NEW_ZONE_ID" > /tmp/target_zone_id.txt

# ==============================================================================
# UI SETUP
# ==============================================================================

# CRITICAL: Ensure WordPress admin page is showing
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi

# Focus and maximize Firefox
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Navigate explicitly to the Shipping settings tab to save time/clicks (optional, but helpful for flow)
# Or let the agent find it. Description says "Navigate to...", so we'll start at Dashboard.
su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' &"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="