#!/bin/bash
echo "=== Exporting configure_security_headers results ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Identify Config File
CONFIG_FILE=$(grep -l "ServerName globex.test" /etc/apache2/sites-available/*.conf | head -n 1)
CONFIG_CONTENT=""
CONFIG_MTIME="0"

if [ -f "$CONFIG_FILE" ]; then
    CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    CONFIG_MTIME=$(stat -c %Y "$CONFIG_FILE")
fi

# 2. Check Apache Status & Syntax
APACHE_RUNNING="false"
if systemctl is-active --quiet apache2; then
    APACHE_RUNNING="true"
fi

CONFIG_SYNTAX_OK="false"
if apache2ctl configtest 2>&1 | grep -q "Syntax OK"; then
    CONFIG_SYNTAX_OK="true"
fi

# 3. Check Live HTTP Headers
# We use --resolve to ensure we hit local Apache even if DNS is weird
CURL_OUTPUT=$(curl -sk -I --resolve "globex.test:443:127.0.0.1" https://globex.test/ 2>&1)

# 4. Check if file was modified during task
FILE_MODIFIED="false"
if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED="true"
fi

# 5. Take final screenshot
take_screenshot /tmp/task_final.png

# 6. Create JSON result
# We use python to safely dump JSON to avoid escaping hell
python3 << EOF
import json
import os

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_file_path": "$CONFIG_FILE",
    "config_content": """$CONFIG_CONTENT""",
    "apache_running": $APACHE_RUNNING,
    "config_syntax_ok": $CONFIG_SYNTAX_OK,
    "curl_output": """$CURL_OUTPUT""",
    "file_modified_during_task": $FILE_MODIFIED,
    "screenshot_path": "/tmp/task_final.png"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="