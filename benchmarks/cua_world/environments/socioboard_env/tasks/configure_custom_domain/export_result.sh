#!/bin/bash
echo "=== Exporting configure_custom_domain result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check /etc/hosts entry
HOSTS_ENTRY=$(grep -E '^127\.0\.0\.1[[:space:]]+.*social\.agency\.local' /etc/hosts >/dev/null && echo "true" || echo "false")
if [ "$HOSTS_ENTRY" = "false" ]; then
    # Try alternate regex allowing leading spaces or variations
    HOSTS_ENTRY=$(grep -E '127\.0\.0\.1[[:space:]]+social\.agency\.local' /etc/hosts >/dev/null && echo "true" || echo "false")
fi

# 3. Check Virtual Host file existence and modification time
VHOST_FILE="/etc/apache2/sites-available/social-agency.conf"
VHOST_EXISTS=$([ -f "$VHOST_FILE" ] && echo "true" || echo "false")

VHOST_MTIME=0
SERVER_NAME_OK="false"
DOCROOT_OK="false"
DIR_BLOCK_OK="false"

if [ "$VHOST_EXISTS" = "true" ]; then
    VHOST_MTIME=$(stat -c %Y "$VHOST_FILE" 2>/dev/null || echo "0")
    
    # Check ServerName
    grep -qiE 'ServerName[[:space:]]+social\.agency\.local' "$VHOST_FILE" && SERVER_NAME_OK="true"
    
    # Check DocumentRoot
    grep -qiE 'DocumentRoot[[:space:]]+"?/opt/socioboard/socioboard-web-php/public"?' "$VHOST_FILE" && DOCROOT_OK="true"
    
    # Check Directory block directives
    if grep -qi 'AllowOverride[[:space:]]\+All' "$VHOST_FILE" && grep -qi 'Require[[:space:]]\+all[[:space:]]\+granted' "$VHOST_FILE"; then
        DIR_BLOCK_OK="true"
    fi
fi

# 4. Check if Vhost is enabled
VHOST_ENABLED=$([ -L "/etc/apache2/sites-enabled/social-agency.conf" ] && echo "true" || echo "false")

# 5. Check Apache configuration syntax
APACHE_VALID=$(apache2ctl configtest 2>&1 | grep -qi "Syntax OK" && echo "true" || echo "false")

# 6. Check HTTP connectivity & content
# Note: We must use --resolve in case the agent failed to update /etc/hosts but did everything else perfectly,
# allowing us to test Apache independently. We'll test BOTH relying on hosts AND forcing resolution.

# 6A. Test relying on system resolution (checks both hosts and apache)
HTTP_CODE_SYSTEM=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://social.agency.local/ 2>/dev/null || echo "000")

HTTP_SUCCESS="false"
if [ "$HTTP_CODE_SYSTEM" = "200" ] || [ "$HTTP_CODE_SYSTEM" = "302" ] || [ "$HTTP_CODE_SYSTEM" = "301" ]; then
    HTTP_SUCCESS="true"
fi

# 6B. Test Content
HTTP_CONTENT_OK="false"
if [ "$HTTP_SUCCESS" = "true" ]; then
    # Check if response contains typical Socioboard UI elements
    CONTENT_CHECK=$(curl -sL --max-time 10 http://social.agency.local/ 2>/dev/null | grep -qiE 'socioboard|login|password|email' && echo "true" || echo "false")
    HTTP_CONTENT_OK="$CONTENT_CHECK"
fi

# 7. Check Socioboard .env APP_URL update
ENV_FILE="/opt/socioboard/socioboard-web-php/.env"
ENV_UPDATED=$(grep -qiE '^APP_URL[[:space:]]*=[[:space:]]*"?http://social\.agency\.local"?' "$ENV_FILE" 2>/dev/null && echo "true" || echo "false")

# 8. Export to JSON
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "hosts_entry": $HOSTS_ENTRY,
    "vhost_exists": $VHOST_EXISTS,
    "vhost_mtime": $VHOST_MTIME,
    "server_name_ok": $SERVER_NAME_OK,
    "docroot_ok": $DOCROOT_OK,
    "dir_block_ok": $DIR_BLOCK_OK,
    "vhost_enabled": $VHOST_ENABLED,
    "apache_valid": $APACHE_VALID,
    "http_code": "$HTTP_CODE_SYSTEM",
    "http_success": $HTTP_SUCCESS,
    "http_content_ok": $HTTP_CONTENT_OK,
    "env_updated": $ENV_UPDATED
}
EOF

# Move safely to /tmp
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "Export completed. Results saved to /tmp/task_result.json"
cat /tmp/task_result.json