#!/bin/bash
echo "=== Exporting create_email_template task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for VLM trajectory verification
take_screenshot /tmp/task_final_state.png

# Read baseline metrics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_template_count.txt 2>/dev/null || echo "0")

# Get current template count
CURRENT_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM email_templates WHERE deleted=0" 2>/dev/null | tr -d '[:space:]' || echo "0")

# Use a PHP script executed inside the SuiteCRM container to safely dump the record as JSON
# This prevents newlines/HTML in the email body from breaking bash variable extraction
cat > /tmp/export_template.php << 'PHPEOF'
<?php
if(!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');

$db = DBManagerFactory::getInstance();
$query = "SELECT id, name, description, subject, body, body_html, UNIX_TIMESTAMP(date_entered) as date_entered_ts FROM email_templates WHERE name='Warranty Claim Response' AND deleted=0 ORDER BY date_entered DESC LIMIT 1";
$result = $db->query($query);
$row = $db->fetchByAssoc($result);

if ($row) {
    $row['template_found'] = true;
} else {
    $row = ['template_found' => false];
}
echo json_encode($row);
?>
PHPEOF

# Copy and execute the script inside the app container
docker cp /tmp/export_template.php suitecrm-app:/var/www/html/export_template.php
TEMPLATE_JSON=$(docker exec suitecrm-app php /var/www/html/export_template.php 2>/dev/null || echo '{"template_found": false}')

# Use Python to safely merge the DB record JSON with our task metrics
python3 -c "
import json
import sys

try:
    data = json.loads('''$TEMPLATE_JSON''')
except Exception as e:
    data = {'template_found': False, 'error': str(e)}

data['task_start_time'] = int('$TASK_START')
data['initial_count'] = int('$INITIAL_COUNT')
data['current_count'] = int('$CURRENT_COUNT')

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Set permissions so verifier can read it
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export generated:"
cat /tmp/task_result.json
echo "=== Export complete ==="