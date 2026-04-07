#!/bin/bash
echo "=== Exporting customize_branding result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot showing agent's progress/final screen
take_screenshot /tmp/task_final.png

SOCR_PHP_DIR="/opt/socioboard/socioboard-web-php"

# Anti-gaming: Find files modified strictly after the task started
# Restrict to resources and public folders to ignore log/cache activity
if [ -d "$SOCR_PHP_DIR/resources" ] && [ -d "$SOCR_PHP_DIR/public" ]; then
    MODIFIED_FILES=$(find "$SOCR_PHP_DIR/resources" "$SOCR_PHP_DIR/public" -type f -newer /tmp/task_start_time.txt 2>/dev/null | wc -l)
else
    MODIFIED_FILES=0
fi

# Clear Laravel view cache so our curl request receives the freshly compiled Blade templates
rm -rf "$SOCR_PHP_DIR/storage/framework/views/"* 2>/dev/null || true

# Fetch HTTP Response from login page
HTTP_RESPONSE=$(curl -sL http://localhost/login 2>/dev/null || curl -sL http://localhost 2>/dev/null)

# Programmatic checks: Grep for required target strings directly in the frontend files
FILE_TITLE=$(grep -ri "Apex Social Hub" "$SOCR_PHP_DIR/resources" "$SOCR_PHP_DIR/public" 2>/dev/null | wc -l)
FILE_LOGIN=$(grep -ri "Welcome to Apex Digital Media" "$SOCR_PHP_DIR/resources" "$SOCR_PHP_DIR/public" 2>/dev/null | wc -l)
FILE_COLOR=$(grep -ri "#1B2A4A" "$SOCR_PHP_DIR/resources" "$SOCR_PHP_DIR/public" 2>/dev/null | wc -l)

# Programmatic checks: Verify the HTML served by the web application contains the targets
HTTP_TITLE="false"
if echo "$HTTP_RESPONSE" | grep -qi "Apex Social Hub"; then HTTP_TITLE="true"; fi

HTTP_LOGIN="false"
if echo "$HTTP_RESPONSE" | grep -qi "Welcome to Apex Digital Media"; then HTTP_LOGIN="true"; fi

# Assemble JSON results into a temporary file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "modified_files_count": $MODIFIED_FILES,
  "file_has_title_count": $FILE_TITLE,
  "file_has_login_count": $FILE_LOGIN,
  "file_has_color_count": $FILE_COLOR,
  "http_has_title": $HTTP_TITLE,
  "http_has_login": $HTTP_LOGIN,
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move securely to prevent permission blocks
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="