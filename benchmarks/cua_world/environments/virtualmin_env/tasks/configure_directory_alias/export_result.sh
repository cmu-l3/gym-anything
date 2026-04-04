#!/bin/bash
echo "=== Exporting configure_directory_alias results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Test HTTP Access (Primary Verification)
TEST_URL="http://acmecorp.test/marketing/press_kit_v1.txt"
HTTP_OUTPUT="/tmp/http_test.txt"
HTTP_CODE=$(curl -s -o "$HTTP_OUTPUT" -w "%{http_code}" "$TEST_URL")
HTTP_CONTENT=$(cat "$HTTP_OUTPUT")

echo "HTTP Check: Code=$HTTP_CODE"

# Check if content matches expected
EXPECTED_SNIPPET="AcmeCorp Official Press Kit"
if echo "$HTTP_CONTENT" | grep -Fq "$EXPECTED_SNIPPET"; then
    CONTENT_MATCH="true"
else
    CONTENT_MATCH="false"
fi

# 2. Check Apache Configuration (Secondary Verification)
CONF_FILE="/etc/apache2/sites-available/acmecorp.test.conf"
ALIAS_FOUND="false"
CONFIG_MODIFIED="false"

if [ -f "$CONF_FILE" ]; then
    # Check modification time
    CONF_MTIME=$(stat -c %Y "$CONF_FILE" 2>/dev/null || echo "0")
    if [ "$CONF_MTIME" -gt "$TASK_START" ]; then
        CONFIG_MODIFIED="true"
    fi

    # Check for Alias directive
    # We look for "Alias /marketing /var/acme_marketing" (ignoring whitespace/quotes)
    if grep -E "Alias\s+/marketing\s+/var/acme_marketing" "$CONF_FILE" > /dev/null; then
        ALIAS_FOUND="true"
    fi
    
    # Check for Redirect (Anti-pattern - user used Redirect instead of Alias)
    if grep -E "Redirect\s+.*\/marketing" "$CONF_FILE" > /dev/null; then
        REDIRECT_FOUND="true"
    else
        REDIRECT_FOUND="false"
    fi
else
    CONF_MTIME="0"
    REDIRECT_FOUND="false"
fi

# 3. Capture final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "http_code": $HTTP_CODE,
    "content_match": $CONTENT_MATCH,
    "alias_found_in_config": $ALIAS_FOUND,
    "redirect_found_in_config": $REDIRECT_FOUND,
    "config_modified_during_task": $CONFIG_MODIFIED,
    "config_path": "$CONF_FILE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="