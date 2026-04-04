#!/bin/bash
set -e
echo "=== Exporting deactivate_user_account results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Query Database for Result
# We fetch relevant fields for the target user
# We look for 'active' (or 'enabled') and 'name'
# Using JSON_OBJECT if available in MySQL 5.7+ for cleaner output, or formatting manually
# Eramba DB usually runs modern MySQL/MariaDB.

# Fetch raw values
USER_DATA=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "
SELECT 
    id, 
    login, 
    name, 
    active, 
    UNIX_TIMESTAMP(modified) 
FROM users 
WHERE login = 'amorgan' 
LIMIT 1;
" 2>/dev/null || echo "")

# Parse fields (tab separated)
# ID, LOGIN, NAME, ACTIVE, MODIFIED_TS
ID=$(echo "$USER_DATA" | awk '{print $1}')
LOGIN=$(echo "$USER_DATA" | awk '{print $2}')
# Name might contain spaces, so we cut from 3rd field to 2nd-to-last
# A safer way with awk given known columns:
# However, for simplicity let's assume standard formatting or just use python to query if needed.
# Let's use a read loop for safety with spaces
read -r DB_ID DB_LOGIN DB_NAME DB_ACTIVE DB_MODIFIED <<< $(echo "$USER_DATA" | awk -F'\t' '{print $1, $2, $3, $4, $5}')

# Re-fetch name specifically to handle spaces correctly
DB_NAME=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT name FROM users WHERE login='amorgan'" 2>/dev/null)

# Check if app is running
APP_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    APP_RUNNING="true"
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "user_found": $(if [ -n "$ID" ]; then echo "true"; else echo "false"; fi),
    "user_id": "$DB_ID",
    "user_login": "$DB_LOGIN",
    "user_name": "$DB_NAME",
    "user_active": "$DB_ACTIVE",
    "record_modified_ts": "${DB_MODIFIED:-0}",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="