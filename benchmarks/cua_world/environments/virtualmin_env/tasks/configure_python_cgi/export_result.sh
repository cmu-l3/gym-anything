#!/bin/bash
echo "=== Exporting configure_python_cgi result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Functional Verification: Try to execute the script
TEST_URL="http://acmecorp.test/agent_test.py"
RESPONSE_FILE="/tmp/curl_response.txt"
HEADERS_FILE="/tmp/curl_headers.txt"

# Run curl, save output and headers
curl -s -D "$HEADERS_FILE" -o "$RESPONSE_FILE" "$TEST_URL" || echo "Curl failed" > "$RESPONSE_FILE"

# Analyze Response
HTTP_STATUS=$(head -1 "$HEADERS_FILE" | grep -o "[0-9]\{3\}" || echo "000")
RESPONSE_BODY=$(cat "$RESPONSE_FILE")

# Check for success token
EXECUTION_SUCCESS="false"
if echo "$RESPONSE_BODY" | grep -q "VERIFICATION_SUCCESS_TOKEN_8392"; then
    EXECUTION_SUCCESS="true"
fi

# Check if source code is visible (failure condition)
# We check for the python print statement which shouldn't be in the output if executed
SOURCE_VISIBLE="false"
if echo "$RESPONSE_BODY" | grep -q 'print("Content-type'; then
    SOURCE_VISIBLE="true"
fi

# 2. Config Verification: Check Apache config for .py handler
CONFIG_UPDATED="false"
CONF_FILE="/etc/apache2/sites-available/acmecorp.test.conf"
if [ -f "$CONF_FILE" ]; then
    # Look for AddHandler cgi-script ... .py ...
    if grep -E "AddHandler\s+cgi-script\s+.*\ .py" "$CONF_FILE"; then
        CONFIG_UPDATED="true"
    fi
    # Also check the Virtualmin specific config pattern
    if grep -E "AddHandler\s+fcgid-script\s+.*\ .py" "$CONF_FILE"; then
        CONFIG_UPDATED="true"
    fi
fi

# 3. Site Stability Check: Check if homepage still loads
INDEX_URL="http://acmecorp.test/"
INDEX_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$INDEX_URL" || echo "000")
SITE_STABLE="false"
if [ "$INDEX_STATUS" -eq "200" ]; then
    SITE_STABLE="true"
fi

# 4. App State Check
APP_RUNNING="false"
if firefox_is_running; then
    APP_RUNNING="true"
fi

# 5. Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "execution_success": $EXECUTION_SUCCESS,
    "source_visible": $SOURCE_VISIBLE,
    "http_status": $HTTP_STATUS,
    "config_updated": $CONFIG_UPDATED,
    "site_stable": $SITE_STABLE,
    "app_running": $APP_RUNNING,
    "response_body_preview": "$(echo "$RESPONSE_BODY" | head -c 100 | xargs)"
}
EOF

# Move to safe location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="