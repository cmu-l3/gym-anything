#!/bin/bash
echo "=== Exporting configure_user_profile_signature results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/configure_profile_final.png

# Create a PHP script to safely extract serialized preferences and user/signature data
cat > /tmp/extract_profile_data.php << 'EOF'
<?php
if(!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');

$db = DBManagerFactory::getInstance();

// 1. Get User object to safely read preferences
$user = BeanFactory::getBean('Users', '1');

// 2. Get direct database values for profile fields
$res = $db->query("SELECT title, department, phone_work, UNIX_TIMESTAMP(date_modified) as mtime FROM users WHERE id='1'");
$user_row = $db->fetchByAssoc($res);

// 3. Get the most recent active signature matching the expected name
$res2 = $db->query("SELECT name, signature_html, UNIX_TIMESTAMP(date_entered) as ctime FROM users_signatures WHERE name='Support Standard' AND deleted=0 ORDER BY date_entered DESC LIMIT 1");
$sig_row = $db->fetchByAssoc($res2);

// Compile result array
$out = array(
    'prefs' => array(
        'datef' => $user->getPreference('datef'),
        'timef' => $user->getPreference('timef')
    ),
    'user' => $user_row ? $user_row : array(),
    'signature' => $sig_row ? $sig_row : array()
);

echo json_encode($out);
?>
EOF

# Execute the PHP script inside the SuiteCRM container
docker cp /tmp/extract_profile_data.php suitecrm-app:/var/www/html/extract_profile_data.php
DB_JSON=$(docker exec -u www-data suitecrm-app php /var/www/html/extract_profile_data.php 2>/dev/null || echo "{}")

# Wrap into the final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << JSONEOF
{
  "task_start_time": $TASK_START,
  "suitecrm_data": $DB_JSON
}
JSONEOF

safe_write_result "/tmp/task_result.json" "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export complete ==="