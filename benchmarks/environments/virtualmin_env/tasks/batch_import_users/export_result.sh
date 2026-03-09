#!/bin/bash
echo "=== Exporting task results: batch_import_users@1 ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

DOMAIN="acmecorp.test"

# 1. Get Initial Count
INITIAL_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")

# 2. Get Final Count
FINAL_COUNT=$(virtualmin list-users --domain "$DOMAIN" --name-only 2>/dev/null | wc -l)

# 3. Get Full User List with Details (JSON format if possible, otherwise text)
# We'll use multiline text output and parse it in python verifier
USER_LIST_TEXT=$(virtualmin list-users --domain "$DOMAIN" --multiline 2>/dev/null)

# 4. Check specific users existence and creation time
# Note: virtualmin list-users doesn't give creation time easily, 
# but we can check the unix user creation time in /etc/passwd or /var/log/auth.log if needed.
# For now, we trust the final state + ID check.

# 5. Take final screenshot
take_screenshot /tmp/task_final.png

# 6. Create JSON result
# We escape the multiline text for JSON safety
ESCAPED_USER_LIST=$(json_escape "$USER_LIST_TEXT")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_user_count": $INITIAL_COUNT,
    "final_user_count": $FINAL_COUNT,
    "user_list_output": "$ESCAPED_USER_LIST",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="