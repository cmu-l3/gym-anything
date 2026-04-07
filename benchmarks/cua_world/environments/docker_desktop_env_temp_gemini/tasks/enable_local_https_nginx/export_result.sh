#!/bin/bash
# Export script for enable_local_https_nginx
# Verifies SSL handshake, certificate identity, and content

echo "=== Exporting enable_local_https_nginx result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/ssl-task"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if container is running
CONTAINER_RUNNING="false"
if docker ps --format '{{.Names}}' | grep -q "web-server"; then
    CONTAINER_RUNNING="true"
fi

# 3. Check HTTPS Connectivity & Content
HTTPS_ACCESSIBLE="false"
HTTP_CODE="000"
CONTENT_MATCH="false"
SERVED_SERVER_HEADER=""

# Use -k to allow self-signed, --max-time to prevent hanging
RESPONSE=$(curl -k -s -v --max-time 5 https://localhost 2> /tmp/curl_stderr.txt || true)

# Extract HTTP Code from stderr (curl -v outputs headers to stderr)
# Actually, let's use -w for status code
HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" --max-time 5 https://localhost || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    HTTPS_ACCESSIBLE="true"
    # Check content
    if echo "$RESPONSE" | grep -q "Welcome to the Secure Local Site"; then
        CONTENT_MATCH="true"
    fi
fi

# 4. Check Certificate Identity
# We want to see if the server is serving the certificate we generated in setup.
# We download the cert presented by the server.
SERVED_FINGERPRINT=""
EXPECTED_FINGERPRINT=$(cat /tmp/expected_cert_fingerprint.txt 2>/dev/null || echo "none")

echo | openssl s_client -connect localhost:443 -servername localhost 2>/dev/null | openssl x509 -noout -fingerprint -sha256 > /tmp/served_cert_fingerprint.txt || true

if [ -s /tmp/served_cert_fingerprint.txt ]; then
    SERVED_FINGERPRINT=$(cat /tmp/served_cert_fingerprint.txt | cut -d= -f2)
fi

echo "Expected: $EXPECTED_FINGERPRINT"
echo "Served:   $SERVED_FINGERPRINT"

CERT_MATCH="false"
if [ "$EXPECTED_FINGERPRINT" = "$SERVED_FINGERPRINT" ] && [ -n "$EXPECTED_FINGERPRINT" ]; then
    CERT_MATCH="true"
fi

# 5. Check Configuration Files (Secondary Check)
# Did they modify the files?
COMPOSE_MODIFIED="false"
CONF_MODIFIED="false"

if [ -f "$PROJECT_DIR/docker-compose.yml" ]; then
    MTIME=$(stat -c %Y "$PROJECT_DIR/docker-compose.yml")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        COMPOSE_MODIFIED="true"
    fi
fi

if [ -f "$PROJECT_DIR/nginx/default.conf" ]; then
    MTIME=$(stat -c %Y "$PROJECT_DIR/nginx/default.conf")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        CONF_MODIFIED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "container_running": $CONTAINER_RUNNING,
    "https_accessible": $HTTPS_ACCESSIBLE,
    "http_code": "$HTTP_CODE",
    "content_match": $CONTENT_MATCH,
    "cert_match": $CERT_MATCH,
    "served_fingerprint": "$SERVED_FINGERPRINT",
    "compose_modified": $COMPOSE_MODIFIED,
    "conf_modified": $CONF_MODIFIED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="