#!/bin/bash
set -e
echo "=== Exporting sanitize_credential_leak result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

TARGET_THREAD_ID=$(cat /tmp/target_thread_id.txt 2>/dev/null || echo "")
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -z "$TARGET_THREAD_ID" ]; then
    echo "ERROR: Target thread ID not found."
    # Create empty result to fail gracefully in verifier
    echo '{"error": "Target thread ID missing"}' > /tmp/task_result.json
    exit 0
fi

echo "Verifying thread ID: $TARGET_THREAD_ID"

# Fetch thread data using raw SQL
# UNIX_TIMESTAMP(updated_at) ensures we get an integer we can compare with bash easily
# NULL deleted_at means it's active
THREAD_DATA=$(fs_query "SELECT body, IFNULL(deleted_at, 'NULL'), UNIX_TIMESTAMP(updated_at) FROM threads WHERE id=$TARGET_THREAD_ID")

# Prepare JSON variables
THREAD_FOUND="false"
BODY=""
DELETED_AT="NULL"
UPDATED_AT="0"

if [ -n "$THREAD_DATA" ]; then
    THREAD_FOUND="true"
    # Extract fields (tab separated by fs_query)
    # Use perl for robust body extraction if it contains tabs/newlines, 
    # but fs_query usually handles simple selects ok. 
    # For safety, we'll just read the raw output carefully.
    
    # We'll re-fetch specific fields to avoid parsing complex body with awk if it contains tabs
    BODY=$(fs_query "SELECT body FROM threads WHERE id=$TARGET_THREAD_ID")
    DELETED_AT=$(fs_query "SELECT IFNULL(deleted_at, 'NULL') FROM threads WHERE id=$TARGET_THREAD_ID")
    UPDATED_AT=$(fs_query "SELECT UNIX_TIMESTAMP(updated_at) FROM threads WHERE id=$TARGET_THREAD_ID")
fi

# Escape body for JSON (escape quotes and backslashes)
# Using python for reliable escaping
ESCAPED_BODY=$(python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" <<< "$BODY")

# Determine if file was created/modified during task
UPDATED_DURING_TASK="false"
if [ "$UPDATED_AT" -gt "$START_TIME" ]; then
    UPDATED_DURING_TASK="true"
fi

# Determine if soft deleted
IS_DELETED="false"
if [ "$DELETED_AT" != "NULL" ] && [ "$DELETED_AT" != "" ]; then
    IS_DELETED="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "thread_found": $THREAD_FOUND,
    "thread_id": "$TARGET_THREAD_ID",
    "body_content": $ESCAPED_BODY,
    "is_deleted": $IS_DELETED,
    "updated_timestamp": $UPDATED_AT,
    "task_start_timestamp": $START_TIME,
    "updated_during_task": $UPDATED_DURING_TASK
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="