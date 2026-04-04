#!/bin/bash
# Setup script for Enforce Checkout Registration task
echo "=== Setting up enforce_checkout_registration ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure services are running
ensure_services_running 120

# Check if Drush works
if ! cd /var/www/html/drupal && vendor/bin/drush status > /dev/null 2>&1; then
    echo "ERROR: Drush is not working"
    exit 1
fi

DRUSH="/var/www/html/drupal/vendor/bin/drush"
DRUPAL_ROOT="/var/www/html/drupal"

echo "Resetting Checkout Flow configuration to initial state (Guest=True, Reg=False)..."
cd "$DRUPAL_ROOT"

# We need to modify the configuration object 'commerce_checkout_flow.default'
# The structure is nested: configuration.panes.login.allow_guest_checkout
# We use drush config:set to ensure the starting state is 'wrong' so the agent has to fix it.

# Set Allow Guest Checkout = TRUE (1)
$DRUSH config:set commerce_checkout_flow.default configuration.panes.login.allow_guest_checkout 1 --yes

# Set Allow Registration = FALSE (0)
$DRUSH config:set commerce_checkout_flow.default configuration.panes.login.allow_registration 0 --yes

# Clear cache to ensure UI reflects this
$DRUSH cr

# Record initial state for verification (anti-gaming)
INITIAL_CONFIG=$($DRUSH config:get commerce_checkout_flow.default --format=json)
echo "$INITIAL_CONFIG" > /tmp/initial_checkout_config.json

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Ensure Firefox is open and navigated to the Checkout Flows page
# This helps the agent start in the right place
echo "Navigating Firefox to Checkout Flows page..."
ensure_drupal_shown 60
navigate_firefox_to "http://localhost/admin/commerce/config/checkout-flows"
sleep 5

# Focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Checkout flow reset: Guest Checkout Allowed, Registration Disabled."