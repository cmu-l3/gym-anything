#!/bin/bash
echo "=== Exporting change_user_role results ==="

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Gather Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_GROUP_ID=$(cat /tmp/initial_group_id.txt 2>/dev/null || echo "0")

# 3. Query Database for Final State
# We get group_id and also check if username still exists (integrity check)
DB_RESULT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT group_id, username FROM users WHERE username='demo_provider'")

# Parse result
if [ -n "$DB_RESULT" ]; then
    FINAL_GROUP_ID=$(echo "$DB_RESULT" | awk '{print $1}')
    FINAL_USERNAME=$(echo "$DB_RESULT" | awk '{print $2}')
    USER_EXISTS="true"
else
    FINAL_GROUP_ID="0"
    FINAL_USERNAME=""
    USER_EXISTS="false"
fi

# 4. Create JSON Result
# Using a temp file to avoid permission issues during creation
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_group_id": $INITIAL_GROUP_ID,
    "final_group_id": $FINAL_GROUP_ID,
    "final_username": "$FINAL_USERNAME",
    "user_exists": $USER_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location (ensure readable by verifier via copy_from_env)
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="