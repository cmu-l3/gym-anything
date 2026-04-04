#!/bin/bash
# Setup script for Customize Transactional Email task

echo "=== Setting up Customize Transactional Email Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Reset the specific email settings to WooCommerce defaults to ensure a clean state
# The default array structure for customer_completed_order
# We use WP-CLI for safe serialization
echo "Resetting 'Completed order' email settings to defaults..."
DEFAULT_JSON='{"enabled":"yes","subject":"","heading":"","additional_content":"","email_type":"html"}'

# Update option using WP-CLI (handles serialization)
wp option update woocommerce_customer_completed_order_settings "$DEFAULT_JSON" --format=json --allow-root

# Verify reset
CURRENT_SETTINGS=$(wp option get woocommerce_customer_completed_order_settings --format=json --allow-root)
echo "Initial Settings: $CURRENT_SETTINGS" > /tmp/initial_email_settings.json

# CRITICAL: Ensure WordPress admin page is showing
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi
echo "WordPress admin page confirmed loaded"

# Focus and maximize Firefox window
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