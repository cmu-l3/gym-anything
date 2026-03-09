#!/bin/bash
set -e
echo "=== Setting up configure_accounts_privacy task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure database is accessible
if ! check_db_connection; then
    echo "ERROR: Database connection failed. Waiting..."
    sleep 5
    check_db_connection || exit 1
fi

WP_DIR="/var/www/html/wordpress"
cd "$WP_DIR"

# Set all options to their "wrong" initial state to force the agent to make changes
# This serves as the 'anti-gaming' baseline
echo "Setting initial (incorrect) option values..."
wp option update woocommerce_enable_guest_checkout "yes" --allow-root 2>&1
wp option update woocommerce_enable_checkout_login_reminder "no" --allow-root 2>&1
wp option update woocommerce_enable_signup_and_login_from_checkout "no" --allow-root 2>&1
wp option update woocommerce_enable_myaccount_registration "no" --allow-root 2>&1
wp option update woocommerce_erasure_request_removes_order_data "no" --allow-root 2>&1
wp option update woocommerce_erasure_request_removes_download_data "no" --allow-root 2>&1

# Record initial values to a JSON file for the verifier to check against
cat > /tmp/initial_account_settings.json << EOF
{
  "guest_checkout": "yes",
  "login_reminder": "no",
  "checkout_signup": "no",
  "myaccount_signup": "no",
  "erase_orders": "no",
  "erase_downloads": "no"
}
EOF

echo "Initial settings recorded:"
cat /tmp/initial_account_settings.json

# CRITICAL: Ensure WordPress admin page is showing
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
fi

# Focus and maximize Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="