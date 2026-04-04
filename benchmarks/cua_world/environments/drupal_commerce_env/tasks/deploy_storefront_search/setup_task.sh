#!/bin/bash
# Setup script for deploy_storefront_search task

echo "=== Setting up deploy_storefront_search ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure services are running
ensure_services_running 120

# 2. Check if the view already exists (it shouldn't)
# We use Drush to check config. If it exists, we delete it to ensure clean state.
echo "Checking for existing 'catalog_search' view..."
if cd /var/www/html/drupal && vendor/bin/drush config:get views.view.catalog_search > /dev/null 2>&1; then
    echo "WARNING: View catalog_search already exists. Deleting..."
    cd /var/www/html/drupal && vendor/bin/drush config:delete views.view.catalog_search -y
fi

# 3. Record start time
date +%s > /tmp/task_start_time.txt

# 4. Ensure Drupal admin is shown
if ! ensure_drupal_shown 60; then
    echo "WARNING: Could not confirm Drupal admin page via window title"
fi

# 5. Navigate to Views creation page to help the agent start
echo "Navigating to Views list..."
navigate_firefox_to "http://localhost/admin/structure/views"
sleep 5

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="