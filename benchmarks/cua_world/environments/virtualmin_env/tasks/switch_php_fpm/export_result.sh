#!/bin/bash
echo "=== Exporting switch_php_fpm results ==="

source /workspace/scripts/task_utils.sh

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check PHP Execution Mode via CLI
# Output format: "PHP execution mode: FCGID (run as greenleaf)" or "FPM"
CURRENT_MODE_LINE=$(virtualmin list-domains --domain greenleaf.test --multiline | grep "PHP execution mode")
CURRENT_MODE=$(echo "$CURRENT_MODE_LINE" | grep -io "fpm" || echo "other")
if [ "$CURRENT_MODE" == "fpm" ]; then
    IS_FPM="true"
else
    IS_FPM="false"
fi

# 2. Find and Check FPM Pool Configuration
# Pool files usually in /etc/php/X.X/fpm/pool.d/1234567890.conf (based on domain ID)
# We search for a file containing the domain name in pool directories
POOL_FILE=$(find /etc/php -name "*.conf" -path "*/pool.d/*" -print0 | xargs -0 grep -l "greenleaf" | head -n 1)

POOL_EXISTS="false"
MAX_CHILDREN_VAL="0"

if [ -f "$POOL_FILE" ]; then
    POOL_EXISTS="true"
    # Extract pm.max_children value. format: pm.max_children = 5
    MAX_CHILDREN_VAL=$(grep "^pm.max_children" "$POOL_FILE" | awk -F'=' '{print $2}' | tr -d ' ;')
fi

# 3. Check PHP-FPM Service Status
SERVICE_ACTIVE="false"
if systemctl is-active --quiet php*-fpm; then
    SERVICE_ACTIVE="true"
fi

# 4. Functional Test: Check PHP API via HTTP
# We verify if the server actually serves PHP via FPM
PHP_API_RESPONSE="unknown"
if curl -s -I "http://greenleaf.test/phpinfo.php" | grep -q "200 OK"; then
    # Parse the phpinfo output for "Server API"
    # We use a small inline php script to extract just the Server API from the server itself if possible,
    # or rely on the output of phpinfo page.
    # Parsing HTML is messy, let's look for the string "FPM/FastCGI" in the raw output
    CONTENT=$(curl -s "http://greenleaf.test/phpinfo.php")
    if echo "$CONTENT" | grep -q "FPM/FastCGI"; then
        PHP_API_RESPONSE="FPM/FastCGI"
    elif echo "$CONTENT" | grep -q "CGI/FastCGI"; then
        PHP_API_RESPONSE="CGI/FastCGI" # Could be FCGID
    elif echo "$CONTENT" | grep -q "Apache 2.0 Handler"; then
        PHP_API_RESPONSE="Apache"
    fi
fi

# 5. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "is_fpm_configured": $IS_FPM,
    "pool_file_exists": $POOL_EXISTS,
    "pool_file_path": "$POOL_FILE",
    "max_children_value": "$MAX_CHILDREN_VAL",
    "service_active": $SERVICE_ACTIVE,
    "php_api_response": "$PHP_API_RESPONSE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved:"
cat /tmp/task_result.json
echo "=== Export complete ==="