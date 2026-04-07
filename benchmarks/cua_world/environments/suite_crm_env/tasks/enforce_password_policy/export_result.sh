#!/bin/bash
echo "=== Exporting enforce_password_policy results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Extract the current password settings directly from SuiteCRM config
cat > /tmp/get_pwd_config.php << 'EOF'
<?php
error_reporting(0);
if(!defined('sugarEntry')) define('sugarEntry', true);
require_once('include/entryPoint.php');

global $sugar_config;
$pwd_settings = isset($sugar_config['passwordsetting']) ? $sugar_config['passwordsetting'] : array();

// Also check config_override.php file modification time
$mtime = file_exists('config_override.php') ? filemtime('config_override.php') : 0;

$result = array(
    'passwordsetting' => $pwd_settings,
    'config_mtime' => $mtime
);

echo json_encode($result);
EOF

docker cp /tmp/get_pwd_config.php suitecrm-app:/tmp/get_pwd_config.php
CONFIG_JSON=$(docker exec suitecrm-app php /tmp/get_pwd_config.php 2>/dev/null)

if [ -z "$CONFIG_JSON" ] || [ "$CONFIG_JSON" == "null" ]; then
    CONFIG_JSON="{}"
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_data": $CONFIG_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Use task_utils to safely write the JSON to the expected location
safe_write_result "/tmp/password_policy_result.json" "$(cat "$TEMP_JSON")"
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/password_policy_result.json"
cat /tmp/password_policy_result.json
echo ""
echo "=== enforce_password_policy export complete ==="