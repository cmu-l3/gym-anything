#!/bin/bash
echo "=== Exporting configure_email_forwarding result ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Virtualmin CLI state for the user
echo "Querying Virtualmin user state..."
USER_INFO=$(virtualmin list-users --domain acmecorp.test --user sarah --multiline 2>/dev/null)

# 2. Check .forward file directly (if it exists)
SARAH_HOME=$(cat /tmp/sarah_home_path.txt 2>/dev/null)
FORWARD_FILE="${SARAH_HOME}/.forward"
FORWARD_CONTENT=""
FORWARD_MTIME="0"

if [ -f "$FORWARD_FILE" ]; then
    FORWARD_CONTENT=$(cat "$FORWARD_FILE")
    FORWARD_MTIME=$(stat -c %Y "$FORWARD_FILE" 2>/dev/null || echo "0")
fi

# 3. Check /etc/aliases or Postfix virtual mapping (alternative storage)
# Virtualmin sometimes puts forwards here depending on configuration
POSTFIX_MAPS=$(grep "sarah@acmecorp.test" /etc/postfix/virtual 2>/dev/null || echo "")

# 4. Take final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import os
import sys

# Safe string reading
def safe_read(val):
    return val if val else ''

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'user_info_cli': '''$USER_INFO''',
    'forward_file_exists': os.path.exists('$FORWARD_FILE'),
    'forward_content': '''$FORWARD_CONTENT''',
    'forward_mtime': $FORWARD_MTIME,
    'postfix_maps': '''$POSTFIX_MAPS''',
    'screenshot_path': '/tmp/task_final.png'
}

print(json.dumps(result))
" > "$TEMP_JSON"

# Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"