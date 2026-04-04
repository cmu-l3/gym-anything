#!/bin/bash
# Setup script for setup_customer_sidebar task

echo "=== Setting up setup_customer_sidebar ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Ensure Drupal services are up
ensure_services_running 120

# Record start time
date +%s > /tmp/task_start_timestamp

# Record initial block configuration state to detect changes
# We count blocks in the sidebar region for the default theme (olivero)
echo "Recording initial block state..."
$DRUSH php:eval "
\$theme = \Drupal::config('system.theme')->get('default');
\$blocks = \Drupal::entityTypeManager()->getStorage('block')->loadByProperties(['theme' => \$theme, 'region' => 'sidebar']);
echo count(\$blocks);
" > /tmp/initial_sidebar_block_count 2>/dev/null || echo "0" > /tmp/initial_sidebar_block_count

echo "Initial sidebar block count: $(cat /tmp/initial_sidebar_block_count)"

# Ensure Drupal admin page is shown
ensure_drupal_shown 60

# Navigate to Block Layout page to save the agent a click
echo "Navigating to Block Layout..."
navigate_firefox_to "http://localhost/admin/structure/block"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="