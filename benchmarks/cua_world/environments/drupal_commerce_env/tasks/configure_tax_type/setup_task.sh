#!/bin/bash
# Setup script for configure_tax_type task
# Ensures Drupal Commerce services are running and navigates to the Tax Types configuration page

echo "=== Setting up Configure Tax Type Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_timestamp

# Ensure all services (Docker, MariaDB, Apache, Firefox) are running
echo "Verifying infrastructure services..."
ensure_services_running 90

# 1. Record initial tax type configurations (to detect new ones later)
# We use drush to list config names starting with commerce_tax.commerce_tax_type
echo "Recording initial tax configurations..."
cd /var/www/html/drupal
vendor/bin/drush config:list --prefix="commerce_tax.commerce_tax_type" --format=json > /tmp/initial_tax_configs.json 2>/dev/null || echo "[]" > /tmp/initial_tax_configs.json

echo "Initial tax configs:"
cat /tmp/initial_tax_configs.json

# 2. Navigate to the Tax Types admin page
# This is the starting point for the agent
echo "Navigating to Commerce > Configuration > Tax types..."
navigate_firefox_to "http://localhost/admin/commerce/config/tax-types"
sleep 5

# 3. Focus and maximize Firefox window for visibility
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 4. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png
echo "Initial screenshot saved"

echo "=== Setup Complete ==="