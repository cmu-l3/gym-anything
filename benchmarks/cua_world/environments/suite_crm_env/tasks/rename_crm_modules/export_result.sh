#!/bin/bash
echo "=== Exporting rename_crm_modules results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create a PHP script to dump the compiled language strings from the active SuiteCRM instance.
# This ensures we are testing the actual live configuration cache, not just database rows.
cat > /tmp/check_lang.php << 'EOF'
<?php
if(!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');

global $app_list_strings;

// Extract the specific labels we care about
$res = array(
    'accounts_singular' => isset($app_list_strings['moduleListSingular']['Accounts']) ? $app_list_strings['moduleListSingular']['Accounts'] : '',
    'accounts_plural' => isset($app_list_strings['moduleList']['Accounts']) ? $app_list_strings['moduleList']['Accounts'] : '',
    'opportunities_singular' => isset($app_list_strings['moduleListSingular']['Opportunities']) ? $app_list_strings['moduleListSingular']['Opportunities'] : '',
    'opportunities_plural' => isset($app_list_strings['moduleList']['Opportunities']) ? $app_list_strings['moduleList']['Opportunities'] : ''
);

echo json_encode($res);
?>
EOF

# Copy script into the container and execute it
docker cp /tmp/check_lang.php suitecrm-app:/tmp/check_lang.php
LANG_JSON=$(docker exec -u www-data suitecrm-app php /tmp/check_lang.php 2>/dev/null || echo "{}")

# Check modification time of the compiled extension language file to detect "do nothing" agents
FILE_MTIME=$(docker exec suitecrm-app stat -c %Y custom/application/Ext/Language/en_us.lang.ext.php 2>/dev/null || echo "0")
if [ "$FILE_MTIME" = "0" ]; then
    # Fallback check on the include custom language file if Ext wasn't updated
    FILE_MTIME=$(docker exec suitecrm-app stat -c %Y custom/include/language/en_us.lang.php 2>/dev/null || echo "0")
fi

# Package everything into a tidy JSON result using jq
jq --arg ts "$TASK_START" \
   --arg te "$TASK_END" \
   --arg mtime "$FILE_MTIME" \
   '. + {task_start: ($ts|tonumber), task_end: ($te|tonumber), file_mtime: ($mtime|tonumber)}' \
   <<< "$LANG_JSON" > /tmp/task_result.json

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== rename_crm_modules export complete ==="