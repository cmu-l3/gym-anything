#!/bin/bash
# Setup script for configure_b2b_registration task
echo "=== Setting up configure_b2b_registration ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure services are running
ensure_services_running 90

# Ensure Drupal admin page is showing
echo "Ensuring Drupal admin page is displayed..."
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# Reset to a clean state if necessary (remove fields if they exist from previous run)
# This ensures the agent actually does the work
echo "Checking for existing fields to clean up..."
if [ -d "/var/www/html/drupal" ]; then
    cd /var/www/html/drupal
    
    # Check if fields exist and delete them to force fresh creation
    if ./vendor/bin/drush field:info user | grep -q "field_company_name"; then
        echo "Cleaning up old company field..."
        ./vendor/bin/drush field:delete user.field_company_name -y 2>/dev/null || true
    fi
    if ./vendor/bin/drush field:info user | grep -q "field_tax_id"; then
        echo "Cleaning up old tax field..."
        ./vendor/bin/drush field:delete user.field_tax_id -y 2>/dev/null || true
    fi
    
    # Delete test user if exists
    if ./vendor/bin/drush user:information b2b_user 2>/dev/null; then
        echo "Cleaning up old test user..."
        ./vendor/bin/drush user:cancel b2b_user --delete-content -y 2>/dev/null || true
    fi

    # Reset registration to 'admin only' (administrators_only)
    ./vendor/bin/drush config:set user.settings register administrators_only -y 2>/dev/null || true
    
    # Clear cache
    ./vendor/bin/drush cr 2>/dev/null || true
fi

# Navigate Firefox to Account Settings as a helpful starting point
# Path: /admin/config/people/accounts
echo "Navigating to Account Settings..."
navigate_firefox_to "http://localhost/admin/config/people/accounts"
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