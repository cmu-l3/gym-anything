#!/bin/bash
echo "=== Exporting modify_php_config results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Method A: Check via Virtualmin CLI (Configuration Files)
# This checks what is written in the php.ini files managed by Virtualmin
echo "Checking config via CLI..."
CLI_UPLOAD=$(virtualmin list-php-ini --domain acmecorp.test --ini-name upload_max_filesize --simple 2>/dev/null)
CLI_POST=$(virtualmin list-php-ini --domain acmecorp.test --ini-name post_max_size --simple 2>/dev/null)
CLI_MEMORY=$(virtualmin list-php-ini --domain acmecorp.test --ini-name memory_limit --simple 2>/dev/null)
CLI_TIME=$(virtualmin list-php-ini --domain acmecorp.test --ini-name max_execution_time --simple 2>/dev/null)

# 3. Method B: Check via Live Runtime (Verification Script)
# This verifies that the settings are actually effective for the web server
echo "Checking runtime values..."
WEB_ROOT="/home/acmecorp/public_html"
VERIFY_SCRIPT="verify_config_$(date +%s).php"
VERIFY_PATH="$WEB_ROOT/$VERIFY_SCRIPT"

# Create a temporary PHP script to output current settings as JSON
cat > "$VERIFY_PATH" << 'EOF'
<?php
header('Content-Type: application/json');
$config = [
    'upload_max_filesize' => ini_get('upload_max_filesize'),
    'post_max_size' => ini_get('post_max_size'),
    'memory_limit' => ini_get('memory_limit'),
    'max_execution_time' => ini_get('max_execution_time')
];
echo json_encode($config);
?>
EOF

# Ensure permissions are correct
chown acmecorp:acmecorp "$VERIFY_PATH" 2>/dev/null || true
chmod 644 "$VERIFY_PATH" 2>/dev/null || true

# Ensure local resolution
if ! grep -q "acmecorp.test" /etc/hosts; then
    echo "127.0.0.1 acmecorp.test" >> /etc/hosts
fi

# Query the script
RUNTIME_JSON=$(curl -s -k "http://acmecorp.test/$VERIFY_SCRIPT")

# Clean up
rm -f "$VERIFY_PATH"

# 4. Anti-Gaming: Check timestamps
# Verify that the php.ini file was modified AFTER the task started
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PHP_INI_PATH="/home/acmecorp/etc/php.ini" # Default location, might vary by PHP mode
# Try to find the actual loaded ini if possible, or check common locations
FOUND_INI=""
for ini in /home/acmecorp/etc/php.ini /home/acmecorp/etc/php*/php.ini; do
    if [ -f "$ini" ]; then
        FOUND_INI="$ini"
        break
    fi
done

INI_MODIFIED_TIME=0
if [ -n "$FOUND_INI" ]; then
    INI_MODIFIED_TIME=$(stat -c %Y "$FOUND_INI" 2>/dev/null || echo "0")
fi

WAS_MODIFIED="false"
if [ "$INI_MODIFIED_TIME" -ge "$TASK_START" ]; then
    WAS_MODIFIED="true"
fi

# 5. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "cli_values": {
        "upload_max_filesize": "$(json_escape "$CLI_UPLOAD")",
        "post_max_size": "$(json_escape "$CLI_POST")",
        "memory_limit": "$(json_escape "$CLI_MEMORY")",
        "max_execution_time": "$(json_escape "$CLI_TIME")"
    },
    "runtime_json": $RUNTIME_JSON,
    "anti_gaming": {
        "task_start": $TASK_START,
        "ini_modified_time": $INI_MODIFIED_TIME,
        "was_modified": $WAS_MODIFIED,
        "ini_file": "$FOUND_INI"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
cat /tmp/task_result.json