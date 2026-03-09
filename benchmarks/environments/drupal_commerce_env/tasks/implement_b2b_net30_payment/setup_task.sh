#!/bin/bash
# Setup script for B2B Net 30 Payment task
echo "=== Setting up B2B Net 30 Payment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure services are running
ensure_services_running 90

# Helper to run Drush commands
run_drush() {
    cd /var/www/html/drupal
    /var/www/html/drupal/vendor/bin/drush "$@"
}

# 1. Clean up existing state (idempotency)
echo "Cleaning up any previous task artifacts..."

# Delete user 'corporate_buyer' if exists
if user_exists "corporate_buyer"; then
    echo "Removing existing corporate_buyer user..."
    run_drush user:cancel corporate_buyer --delete-content -y >/dev/null 2>&1 || true
fi

# Delete role 'wholesale_buyer' if exists (check by label or machine name)
# We guess common machine names the agent might generate
for role in wholesale_buyer wholesale; do
    if run_drush role:list --format=json | grep -q "$role"; then
        echo "Removing existing role: $role"
        run_drush role:delete "$role" -y >/dev/null 2>&1 || true
    fi
done

# Delete any payment gateway with 'Net 30' in label
# We need to find the ID first.
# Get list of gateways
GATEWAYS_JSON=$(run_drush config:list --prefix=commerce_payment.commerce_payment_gateway --format=json)
# Loop through (simple approximation)
echo "$GATEWAYS_JSON" | grep -o 'commerce_payment\.commerce_payment_gateway\.[^"]*' | while read -r config_name; do
    # Get the label
    LABEL=$(run_drush config:get "$config_name" label --format=string 2>/dev/null)
    if [[ "$LABEL" == *"Net 30"* ]]; then
        GW_ID=${config_name##*.}
        echo "Removing existing gateway: $GW_ID ($LABEL)"
        # Delete the config entity
        run_drush config:delete "$config_name" -y >/dev/null 2>&1
    fi
done

# Record initial counts
INITIAL_USER_COUNT=$(get_user_count)
# Count roles (approximate via config count)
INITIAL_ROLE_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name LIKE 'user.role.%'")

echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count
echo "$INITIAL_ROLE_COUNT" > /tmp/initial_role_count

# Record timestamp
date +%s > /tmp/task_start_time.txt

# Ensure Drupal admin is reachable and logged in
echo "Navigating to Commerce Configuration..."
navigate_firefox_to "http://localhost/admin/commerce/config/payment-gateways"
sleep 5

# Focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="