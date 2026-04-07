#!/bin/bash
echo "=== Setting up create_custom_field task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Idempotent Cleanup: Ensure the target field and dropdown don't already exist
echo "Cleaning up any prior state..."
suitecrm_db_query "DELETE FROM fields_meta_data WHERE name LIKE '%preferred_contact_method%';" 2>/dev/null || true
suitecrm_db_query "ALTER TABLE contacts_cstm DROP COLUMN preferred_contact_method_c;" 2>/dev/null || true

# Delete compiled language extensions related to this custom field
docker exec suitecrm-app bash -c "find /var/www/html/custom -type f -name '*preferred_contact_method*' -delete" 2>/dev/null || true
# Rebuild relationships/extensions (silent via PHP) to fully clear cache
cat > /tmp/rebuild.php << 'PHPEOF'
<?php
if(!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');
require_once('modules/Administration/QuickRepairAndRebuild.php');
$RAC = new RepairAndClear();
$RAC->repairAndClearAll(array('clearAll'), array(translate('LBL_ALL_MODULES')), false, false);
PHPEOF
docker cp /tmp/rebuild.php suitecrm-app:/tmp/rebuild.php
docker exec suitecrm-app php /tmp/rebuild.php >/dev/null 2>&1 || true

# 3. Ensure logged in and navigate to Studio
# Bypassing directly to Studio saves the agent initial navigation time so they can focus on the form builder
echo "Navigating to SuiteCRM Studio..."
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=ModuleBuilder&action=index&type=studio"
sleep 5

# 4. Take initial screenshot
take_screenshot /tmp/create_custom_field_initial.png

echo "=== create_custom_field task setup complete ==="
echo "Task: Create the 'Preferred Contact Method' dropdown field in Contacts module via Studio."