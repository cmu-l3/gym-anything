#!/bin/bash
echo "=== Setting up enable_field_auditing task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure a clean state: Remove any existing custom auditing for these fields
echo "Cleaning up any pre-existing field configurations..."
docker exec suitecrm-app rm -f /var/www/html/custom/Extension/modules/Accounts/Ext/Vardefs/sugarfield_industry.php
docker exec suitecrm-app rm -f /var/www/html/custom/Extension/modules/Accounts/Ext/Vardefs/sugarfield_annual_revenue.php

# Flush the Account vardefs cache to ensure standard state
docker exec suitecrm-app rm -rf /var/www/html/cache/modules/Accounts/Accountvardefs.php

# Run a quick repair and rebuild on the Accounts module to commit the clean state
cat > /tmp/clean_repair.php << 'PHPEOF'
<?php
define('sugarEntry', true);
require_once('include/entryPoint.php');
require_once('modules/Administration/QuickRepairAndRebuild.php');
$repair = new RepairAndClear();
$repair->repairAndClearAll(array('clearAll'), array('Accounts'), false, false);
PHPEOF
docker cp /tmp/clean_repair.php suitecrm-app:/tmp/clean_repair.php
docker exec suitecrm-app sudo -u www-data php /tmp/clean_repair.php > /dev/null 2>&1 || true

# 3. Ensure logged in and navigate to the Home dashboard
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"
sleep 4

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== enable_field_auditing task setup complete ==="