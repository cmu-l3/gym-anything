#!/bin/bash
echo "=== Exporting harden_apache_global_config result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------
# 1. LIVE VERIFICATION (The most important part)
# ---------------------------------------------------------

# Check Server header (Should be just "Apache")
# curl -I returns headers. grep "Server:".
SERVER_HEADER=$(curl -sI http://localhost | grep "Server:" | tr -d '\r')
# Expected: "Server: Apache"

# Check ServerSignature (Should be off)
# Request a non-existent page. If Signature is On, it appears at the bottom.
# We look for "Apache/2.4" or similar version numbers which appear when Signature is On.
ERROR_PAGE_CONTENT=$(curl -s http://localhost/non_existent_page_$(date +%s))
if echo "$ERROR_PAGE_CONTENT" | grep -q "Apache/2.4"; then
    SIGNATURE_VISIBLE="true"
else
    SIGNATURE_VISIBLE="false"
fi

# Check TraceEnable (Should be Off)
# Request with TRACE method.
# If On: returns 200 OK and reflects body.
# If Off: returns 405 Method Not Allowed or 403 Forbidden.
TRACE_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X TRACE http://localhost)

# ---------------------------------------------------------
# 2. CONFIGURATION FILE VERIFICATION
# ---------------------------------------------------------
# We check /etc/apache2/conf-enabled/security.conf and apache2.conf
# We look for the directives.

CONF_FILE="/etc/apache2/conf-enabled/security.conf"
MAIN_CONF="/etc/apache2/apache2.conf"

# Helper to find directive in common files
find_directive() {
    local pattern="$1"
    grep -ri "$pattern" /etc/apache2/conf-enabled/ /etc/apache2/apache2.conf /etc/apache2/sites-enabled/ 2>/dev/null | head -1
}

CONFIG_TOKENS=$(find_directive "^ServerTokens[[:space:]]\+Prod")
CONFIG_SIGNATURE=$(find_directive "^ServerSignature[[:space:]]\+Off")
CONFIG_TRACE=$(find_directive "^TraceEnable[[:space:]]\+Off")

# Check file modification time of security.conf
FILE_MTIME=$(stat -c %Y "$CONF_FILE" 2>/dev/null || echo "0")
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    CONFIG_MODIFIED="true"
else
    CONFIG_MODIFIED="false"
fi

# ---------------------------------------------------------
# 3. EXPORT JSON
# ---------------------------------------------------------

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "server_header": "$(json_escape "$SERVER_HEADER")",
    "signature_visible": $SIGNATURE_VISIBLE,
    "trace_http_code": "$TRACE_HTTP_CODE",
    "config_tokens_found": "$(json_escape "$CONFIG_TOKENS")",
    "config_signature_found": "$(json_escape "$CONFIG_SIGNATURE")",
    "config_trace_found": "$(json_escape "$CONFIG_TRACE")",
    "config_modified_during_task": $CONFIG_MODIFIED,
    "task_timestamp": $TASK_END
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="