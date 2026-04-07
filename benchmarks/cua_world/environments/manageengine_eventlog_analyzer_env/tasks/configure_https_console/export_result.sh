#!/bin/bash
echo "=== Exporting Configure HTTPS Console results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check Marker File
MARKER_FILE="/home/ga/https_configured.txt"
MARKER_EXISTS="false"
MARKER_CONTENT=""
MARKER_TIMESTAMP=0

if [ -f "$MARKER_FILE" ]; then
    MARKER_EXISTS="true"
    MARKER_CONTENT=$(cat "$MARKER_FILE")
    MARKER_TIMESTAMP=$(stat -c %Y "$MARKER_FILE")
fi

# 2. Check Network Connectivity (HTTPS on 8443)
# Accept self-signed certs (-k)
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://localhost:8443/event/index.do 2>/dev/null || echo "000")
HTTPS_ACCESSIBLE="false"
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "303" ]; then
    HTTPS_ACCESSIBLE="true"
fi

# 3. Check SSL Handshake explicitly
# verification of actual SSL protocol
SSL_HANDSHAKE_SUCCESS="false"
if timeout 5 openssl s_client -connect localhost:8443 < /dev/null 2>/dev/null | grep -q "BEGIN CERTIFICATE"; then
    SSL_HANDSHAKE_SUCCESS="true"
fi

# 4. Check internal configuration file (server.xml)
# Typical path for ManageEngine products (Tomcat based)
CONF_FILE="/opt/ManageEngine/EventLog/conf/server.xml"
CONF_UPDATED="false"
PORT_CONFIGURED="false"
SSL_ENABLED_CONFIG="false"

if [ -f "$CONF_FILE" ]; then
    # Check modification time
    CONF_MTIME=$(stat -c %Y "$CONF_FILE")
    if [ "$CONF_MTIME" -gt "$TASK_START" ]; then
        CONF_UPDATED="true"
    fi
    
    # Check content for 8443 and secure/scheme attributes
    if grep -q "port=\"8443\"" "$CONF_FILE"; then
        PORT_CONFIGURED="true"
    fi
    if grep -q "scheme=\"https\"" "$CONF_FILE" || grep -q "secure=\"true\"" "$CONF_FILE" || grep -q "SSLEnabled=\"true\"" "$CONF_FILE"; then
        SSL_ENABLED_CONFIG="true"
    fi
fi

# 5. Check if HTTP port 8095 is still open (some configs keep it, some redirect)
HTTP_STILL_OPEN="false"
HTTP_CODE_OLD=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 http://localhost:8095/event/index.do 2>/dev/null || echo "000")
if [ "$HTTP_CODE_OLD" != "000" ]; then
    HTTP_STILL_OPEN="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "marker_exists": $MARKER_EXISTS,
    "marker_content": "$MARKER_CONTENT",
    "marker_created_during_task": $([ "$MARKER_TIMESTAMP" -gt "$TASK_START" ] && echo "true" || echo "false"),
    "https_accessible": $HTTPS_ACCESSIBLE,
    "http_response_code": "$HTTP_CODE",
    "ssl_handshake_success": $SSL_HANDSHAKE_SUCCESS,
    "conf_updated": $CONF_UPDATED,
    "conf_port_8443": $PORT_CONFIGURED,
    "conf_ssl_enabled": $SSL_ENABLED_CONFIG,
    "http_8095_open": $HTTP_STILL_OPEN,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="