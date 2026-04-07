#!/bin/bash
echo "=== Setting up customize_accounts_basic_search task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Remove any existing custom searchdefs for Accounts to ensure a clean state
docker exec suitecrm-app rm -f /var/www/html/custom/modules/Accounts/metadata/searchdefs.php
docker exec suitecrm-app rm -f /var/www/html/cache/modules/Accounts/SearchForm_basic.tpl 2>/dev/null || true
docker exec suitecrm-app rm -f /var/www/html/cache/modules/Accounts/SearchForm_advanced.tpl 2>/dev/null || true

# Ensure user is logged in and on the home page
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="