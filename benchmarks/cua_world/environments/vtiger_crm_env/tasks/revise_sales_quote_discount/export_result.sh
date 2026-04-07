#!/bin/bash
echo "=== Exporting revise_sales_quote_discount results ==="

source /workspace/scripts/task_utils.sh

# Capture timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_quote_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_crmentity WHERE setype='Quotes' AND deleted=0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# PHP Script to cleanly extract quote data using Vtiger DB connection
cat > /tmp/export_quotes.php << 'PHPEOF'
<?php
error_reporting(E_ERROR);
chdir('/var/www/html/vtigercrm');
require_once 'includes/main/WebUI.php';

$adb = PearDatabase::getInstance();

// Fetch Original Quote
$origRes = $adb->pquery("SELECT q.quoteid, q.subject, q.quotestage, q.hdnDiscountPercent FROM vtiger_quotes q INNER JOIN vtiger_crmentity c ON q.quoteid = c.crmid WHERE c.deleted = 0 AND q.subject = 'Q3 Hardware Refresh' ORDER BY c.crmid ASC LIMIT 1", array());

$orig_found = false;
$orig_discount = 0;
if ($adb->num_rows($origRes) > 0) {
    $orig_found = true;
    $orig_discount = floatval($adb->query_result($origRes, 0, 'hdnDiscountPercent'));
}

// Fetch Cloned Quote
$cloneRes = $adb->pquery("SELECT q.quoteid, q.subject, q.quotestage, q.hdnDiscountPercent FROM vtiger_quotes q INNER JOIN vtiger_crmentity c ON q.quoteid = c.crmid WHERE c.deleted = 0 AND q.subject = 'Q3 Hardware Refresh - Revision 1' ORDER BY c.crmid DESC LIMIT 1", array());

$clone_found = false;
$clone_stage = '';
$clone_discount = 0;
if ($adb->num_rows($cloneRes) > 0) {
    $clone_found = true;
    $clone_stage = $adb->query_result($cloneRes, 0, 'quotestage');
    $clone_discount = floatval($adb->query_result($cloneRes, 0, 'hdnDiscountPercent'));
}

$result = array(
    'original_found' => $orig_found,
    'original_discount' => $orig_discount,
    'clone_found' => $clone_found,
    'clone_stage' => $clone_stage,
    'clone_discount' => $clone_discount
);

// Save directly to file to avoid PHP notice pollution in stdout
file_put_contents('/tmp/quote_verification.json', json_encode($result));
?>
PHPEOF

docker cp /tmp/export_quotes.php vtiger-app:/tmp/export_quotes.php
docker exec vtiger-app php /tmp/export_quotes.php
DB_JSON_DATA=$(docker exec vtiger-app cat /tmp/quote_verification.json)

# Check if browser is running
BROWSER_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Construct final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "browser_running": $BROWSER_RUNNING,
    "db_data": $DB_JSON_DATA
}
EOF

# Move to standard location via safe write
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="