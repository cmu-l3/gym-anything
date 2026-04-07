#!/bin/bash
echo "=== Exporting create_grouped_quote task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot "/tmp/task_final.png"

# Read timestamps and counts
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_QUOTE_COUNT=$(cat /tmp/initial_quote_count.txt 2>/dev/null || echo "0")
CURRENT_QUOTE_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM aos_quotes WHERE deleted=0" | tr -d '[:space:]')
if [ -z "$CURRENT_QUOTE_COUNT" ]; then CURRENT_QUOTE_COUNT=0; fi

# Create PHP script to cleanly extract hierarchical quote data natively via SuiteCRM's DBManager
cat > /tmp/export_quote.php << 'PHPEOF'
<?php
if(!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');
global $db;

$result = [
    'quote_found' => false,
    'quote' => null,
    'groups' => [],
    'line_items' => [],
    'account_linked' => false,
    'account_name' => ''
];

$res = $db->query("SELECT id, name, billing_account_id, date_entered FROM aos_quotes WHERE name='Q3 Infrastructure Quote - Tech Data' AND deleted=0 ORDER BY date_entered DESC LIMIT 1");
$quote = $db->fetchByAssoc($res);

if ($quote) {
    $result['quote_found'] = true;
    $result['quote'] = $quote;
    
    // Check account linkage
    if (!empty($quote['billing_account_id'])) {
        $acc_res = $db->query("SELECT name FROM accounts WHERE id='{$quote['billing_account_id']}'");
        $acc = $db->fetchByAssoc($acc_res);
        if ($acc) {
            $result['account_linked'] = true;
            $result['account_name'] = $acc['name'];
        }
    }
    
    // Get groups belonging to this quote
    $g_res = $db->query("SELECT id, name FROM aos_line_item_groups WHERE parent_id='{$quote['id']}' AND deleted=0");
    while($g = $db->fetchByAssoc($g_res)) {
        $result['groups'][] = $g;
    }
    
    // Get line items belonging to this quote (and note which group they are inside)
    $l_res = $db->query("SELECT id, name, product_qty, product_list_price, group_id FROM aos_products_quotes WHERE parent_id='{$quote['id']}' AND deleted=0");
    while($l = $db->fetchByAssoc($l_res)) {
        $result['line_items'][] = $l;
    }
}

echo json_encode($result);
?>
PHPEOF

# Execute PHP script in container to dump DB structure cleanly as JSON
docker cp /tmp/export_quote.php suitecrm-app:/tmp/export_quote.php
DB_DUMP=$(docker exec suitecrm-app php /tmp/export_quote.php 2>/dev/null)

if [ -z "$DB_DUMP" ]; then
    DB_DUMP='{"quote_found": false}'
fi

# Assemble the final result JSON safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start_time": $TASK_START,
  "initial_count": $INITIAL_QUOTE_COUNT,
  "current_count": $CURRENT_QUOTE_COUNT,
  "db_data": $DB_DUMP
}
EOF

# Move to standard location accessible to verifier
rm -f /tmp/create_grouped_quote_result.json 2>/dev/null || sudo rm -f /tmp/create_grouped_quote_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_grouped_quote_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_grouped_quote_result.json
chmod 666 /tmp/create_grouped_quote_result.json 2>/dev/null || sudo chmod 666 /tmp/create_grouped_quote_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/create_grouped_quote_result.json"
echo "=== Export complete ==="