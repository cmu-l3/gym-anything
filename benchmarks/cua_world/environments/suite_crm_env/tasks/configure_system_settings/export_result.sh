#!/bin/bash
echo "=== Exporting configure_system_settings results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/configure_system_settings_final.png

# Create a PHP script to extract the actual settings directly from SuiteCRM's config arrays
# We also check for any newly uploaded images in the themes/upload directory
cat << 'EOF' > /tmp/check_config.php
<?php
$sugar_config = array();
if(file_exists('/var/www/html/config.php')) {
    require('/var/www/html/config.php');
}
if(file_exists('/var/www/html/config_override.php')) {
    require('/var/www/html/config_override.php');
}

$start_ref = file_exists('/tmp/task_start_ref') ? filemtime('/tmp/task_start_ref') : 0;

// SuiteCRM often stores uploaded logos in custom/themes/default/images/
$logo_path = '/var/www/html/custom/themes/default/images/company_logo.png';
$logo_uploaded = false;

if (file_exists($logo_path) && filemtime($logo_path) > $start_ref) {
    $logo_uploaded = true;
} else {
    // Fallback: check upload/ and custom/themes directories for recently modified image files
    $cmd = "find /var/www/html/upload /var/www/html/custom/themes -type f -newer /tmp/task_start_ref 2>/dev/null | grep -iE '\.(png|jpg|jpeg|gif)$' | wc -l";
    $count = (int)trim(shell_exec($cmd));
    if ($count > 0) {
        $logo_uploaded = true;
    }
}

$res = array(
    'system_name' => isset($sugar_config['system_name']) ? $sugar_config['system_name'] : '',
    'list_max_entries_per_page' => isset($sugar_config['list_max_entries_per_page']) ? $sugar_config['list_max_entries_per_page'] : '',
    'lock_homepage' => isset($sugar_config['lock_homepage']) ? $sugar_config['lock_homepage'] : false,
    'logo_uploaded' => $logo_uploaded
);

echo json_encode($res, JSON_PRETTY_PRINT);
?>
EOF

# Copy script into container and execute it
docker cp /tmp/check_config.php suitecrm-app:/tmp/check_config.php
RESULT_JSON=$(docker exec suitecrm-app php /tmp/check_config.php 2>/dev/null || echo '{"error": "Failed to execute PHP check"}')

# Safe write
safe_write_result "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "$RESULT_JSON"
echo "=== Export complete ==="