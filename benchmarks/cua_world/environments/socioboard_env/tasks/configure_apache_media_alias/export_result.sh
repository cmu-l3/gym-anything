#!/bin/bash
echo "=== Exporting configure_apache_media_alias task result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Verify HTTP Access (The ultimate proof it works)
HTTP_URL="http://localhost/stock-media/monarch.jpg"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$HTTP_URL" || echo "000")
HTTP_CONTENT_TYPE=$(curl -s -I "$HTTP_URL" | grep -i "^Content-Type:" | awk '{print $2}' | tr -d '\r\n' || echo "unknown")
HTTP_CONTENT_LENGTH=$(curl -s -I "$HTTP_URL" | grep -i "^Content-Length:" | awk '{print $2}' | tr -d '\r\n' || echo "0")

# 2. Check for File Cheating (Copying into the public document root instead of using Alias)
CHEAT_DIR="/opt/socioboard/socioboard-web-php/public/stock-media"
CHEAT_DIR_EXISTS="false"
if [ -d "$CHEAT_DIR" ]; then
    CHEAT_DIR_EXISTS="true"
fi
CHEAT_FILE_EXISTS="false"
if [ -f "$CHEAT_DIR/monarch.jpg" ]; then
    CHEAT_FILE_EXISTS="true"
fi

# 3. Check Apache Configuration Validity
CONFIG_SYNTAX_OK="false"
if sudo apache2ctl configtest 2>&1 | grep -qi "Syntax OK"; then
    CONFIG_SYNTAX_OK="true"
fi

# 4. Check for explicit Alias directive in Apache configuration files
ALIAS_CONFIGURED="false"
if sudo grep -rEi "^\s*Alias\s+/stock-media" /etc/apache2/ 2>/dev/null | grep -q "/var/lib/agency_stock_media"; then
    ALIAS_CONFIGURED="true"
fi

# Build JSON using a temporary file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "http_status": "$HTTP_STATUS",
    "http_content_type": "$HTTP_CONTENT_TYPE",
    "http_content_length": "$HTTP_CONTENT_LENGTH",
    "cheat_dir_exists": $CHEAT_DIR_EXISTS,
    "cheat_file_exists": $CHEAT_FILE_EXISTS,
    "config_syntax_ok": $CONFIG_SYNTAX_OK,
    "alias_configured": $ALIAS_CONFIGURED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safely move JSON to final accessible location
sudo rm -f /tmp/task_result.json 2>/dev/null || true
sudo cp "$TEMP_JSON" /tmp/task_result.json
sudo chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Exported JSON Result:"
cat /tmp/task_result.json
echo "=== Export complete ==="