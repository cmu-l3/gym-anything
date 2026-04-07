#!/bin/bash
echo "=== Exporting Configure Apache API Proxy Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if required Apache modules are enabled
MOD_PROXY=$(apache2ctl -M 2>/dev/null | grep proxy_module || echo "")
MOD_PROXY_HTTP=$(apache2ctl -M 2>/dev/null | grep proxy_http_module || echo "")

# Read Apache active configuration
APACHE_CONF=""
if [ -f /etc/apache2/sites-available/000-default.conf ]; then
    APACHE_CONF=$(cat /etc/apache2/sites-available/000-default.conf)
fi
# Serialize string safely for JSON
APACHE_CONF_JSON=$(python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))' <<< "$APACHE_CONF")

# Read frontend .env file variables
ENV_FILE="/opt/socioboard/socioboard-web-php/.env"
ENV_API_URL=$(grep "^API_URL=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'")
ENV_API_FEEDS=$(grep "^API_URL_FEEDS=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'")
ENV_API_PUBLISH=$(grep "^API_URL_PUBLISH=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'")
ENV_API_NOTIF=$(grep "^API_URL_NOTIFICATION=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '\r' | tr -d '"' | tr -d "'")

# Verify live proxy endpoints locally via curl
# We inspect HTTP headers to check if the request reached Express (Node.js) through Apache
test_proxy() {
    local path=$1
    local headers=$(curl -s -m 5 -I "http://localhost${path}" 2>/dev/null)
    
    # If the X-Powered-By: Express header is present, Node.js responded
    if echo "$headers" | grep -qi "Express"; then
        echo "true"
    else
        echo "false"
    fi
}

echo "Testing live proxy routing..."
PROXY_USER=$(test_proxy "/proxy/user/")
PROXY_FEEDS=$(test_proxy "/proxy/feeds/")
PROXY_PUBLISH=$(test_proxy "/proxy/publish/")
PROXY_NOTIF=$(test_proxy "/proxy/notification/")

# File modification check
ENV_MTIME=$(stat -c %Y "$ENV_FILE" 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Write results to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "mod_proxy_enabled": $([ -n "$MOD_PROXY" ] && echo "true" || echo "false"),
    "mod_proxy_http_enabled": $([ -n "$MOD_PROXY_HTTP" ] && echo "true" || echo "false"),
    "apache_conf": $APACHE_CONF_JSON,
    "env": {
        "api_url": "$ENV_API_URL",
        "api_feeds": "$ENV_API_FEEDS",
        "api_publish": "$ENV_API_PUBLISH",
        "api_notification": "$ENV_API_NOTIF"
    },
    "live_proxy": {
        "user": $PROXY_USER,
        "feeds": $PROXY_FEEDS,
        "publish": $PROXY_PUBLISH,
        "notification": $PROXY_NOTIF
    },
    "env_mtime": $ENV_MTIME,
    "task_start": $TASK_START
}
EOF

# Make result file available to verifier
rm -f /tmp/apache_proxy_result.json 2>/dev/null || sudo rm -f /tmp/apache_proxy_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/apache_proxy_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/apache_proxy_result.json
chmod 666 /tmp/apache_proxy_result.json 2>/dev/null || sudo chmod 666 /tmp/apache_proxy_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/apache_proxy_result.json"
cat /tmp/apache_proxy_result.json
echo "=== Export Complete ==="