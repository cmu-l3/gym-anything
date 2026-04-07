#!/bin/bash
echo "=== Exporting enable_https_socioboard result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Take a final screenshot
DISPLAY=:1 scrot /tmp/task_end.png 2>/dev/null || true

# 1. Check if port 443 is open and listening
PORT_443_OPEN="false"
if nc -z localhost 443 2>/dev/null || ss -tln | grep -q ":443 "; then
    PORT_443_OPEN="true"
fi

# 2. Check for a valid SSL Handshake on port 443
SSL_HANDSHAKE="false"
if echo -n | openssl s_client -connect localhost:443 2>/dev/null | grep -q "Server certificate"; then
    SSL_HANDSHAKE="true"
fi

# 3. Check HTTP Response code and content for HTTPS Socioboard
# Use -k to ignore self-signed cert validation warnings, -L to follow redirects (like to /login)
HTTPS_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost/ 2>/dev/null || echo "000")
HTTPS_CONTENT_MATCH="false"
if curl -k -s -L https://localhost/ 2>/dev/null | grep -qi "socioboard"; then
    HTTPS_CONTENT_MATCH="true"
fi

# 4. Check application configuration (.env)
ENV_APP_URL=""
ENV_FILE="/opt/socioboard/socioboard-web-php/.env"
if [ -f "$ENV_FILE" ]; then
    # Extract the APP_URL value, removing quotes and carriage returns
    ENV_APP_URL=$(grep "^APP_URL=" "$ENV_FILE" | cut -d '=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'")
fi

# Create a clean JSON result securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "port_443_open": $PORT_443_OPEN,
    "ssl_handshake": $SSL_HANDSHAKE,
    "https_status": "$HTTPS_STATUS",
    "https_content_match": $HTTPS_CONTENT_MATCH,
    "env_app_url": "$ENV_APP_URL",
    "task_start": $TASK_START,
    "task_end": $TASK_END
}
EOF

# Move to the final location and set permissions
mv "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json:"
cat /tmp/task_result.json
echo "=== Export complete ==="