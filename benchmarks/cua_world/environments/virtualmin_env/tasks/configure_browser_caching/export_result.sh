#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Check Apache Module Status
MODULE_ENABLED="false"
if apache2ctl -M 2>/dev/null | grep -q "expires_module"; then
    MODULE_ENABLED="true"
fi

# 3. Check Virtual Host Configuration
CONFIG_CONTAINS_DIRECTIVE="false"
CONF_FILE="/etc/apache2/sites-available/acmecorp.test.conf"
if [ -f "$CONF_FILE" ]; then
    # Check for ExpiresActive and ExpiresDefault
    if grep -iq "ExpiresActive On" "$CONF_FILE" && grep -iq "ExpiresDefault" "$CONF_FILE"; then
        CONFIG_CONTAINS_DIRECTIVE="true"
    fi
    # Read relevant lines for debug/context
    CONFIG_CONTENT=$(grep -i "Expires" "$CONF_FILE" | base64 -w 0)
else
    CONFIG_CONTENT=""
fi

# 4. Check HTTP Headers (The Proof of Pudding)
# We perform a HEAD request to localhost to check the headers
HEADERS_OUTPUT=$(curl -s -I -D - http://acmecorp.test/cache_test.css || echo "CURL_FAILED")
CACHE_CONTROL=$(echo "$HEADERS_OUTPUT" | grep -i "Cache-Control" | tr -d '\r')
EXPIRES_HEADER=$(echo "$HEADERS_OUTPUT" | grep -i "Expires" | tr -d '\r')

# Extract max-age if present
MAX_AGE="0"
if [[ "$CACHE_CONTROL" =~ max-age=([0-9]+) ]]; then
    MAX_AGE="${BASH_REMATCH[1]}"
fi

# 5. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "module_enabled": $MODULE_ENABLED,
    "config_contains_directive": $CONFIG_CONTAINS_DIRECTIVE,
    "config_content_b64": "$CONFIG_CONTENT",
    "http_max_age": $MAX_AGE,
    "cache_control_header": "$(echo "$CACHE_CONTROL" | sed 's/"/\\"/g')",
    "expires_header": "$(echo "$EXPIRES_HEADER" | sed 's/"/\\"/g')",
    "screenshot_path": "/tmp/task_final.png"
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