#!/bin/bash
echo "=== Setting up customize_account_detailview_layout task ==="

source /workspace/scripts/task_utils.sh

# Record precise start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Clean slate: Remove any existing customizations for Accounts DetailView
docker exec suitecrm-app rm -f /var/www/html/custom/modules/Accounts/metadata/detailviewdefs.php 2>/dev/null || true

# Clean slate: Remove any custom labels that might match our target
docker exec suitecrm-app bash -c 'find /var/www/html/custom/modules/Accounts/ -type f -name "*.php" -exec sed -i "/Financial Details/d" {} +' 2>/dev/null || true

# Ensure logged in and navigate to the Administration page
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Administration&action=index"
sleep 3

# Take baseline screenshot
take_screenshot /tmp/customize_layout_initial.png

echo "=== customize_account_detailview_layout task setup complete ==="