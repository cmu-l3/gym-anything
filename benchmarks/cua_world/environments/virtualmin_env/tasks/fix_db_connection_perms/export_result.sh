#!/bin/bash
echo "=== Exporting fix_db_connection_perms result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Target file details
TARGET_FILE="/home/acmecorp/public_html/includes/db_config.php"
TARGET_URL="http://acmecorp.test/status.php"

# 1. Inspect File Permissions
if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    # Get octal permissions (e.g., 644, 777)
    FILE_PERMS=$(stat -c "%a" "$TARGET_FILE")
    FILE_MTIME=$(stat -c "%Y" "$TARGET_FILE")
    
    # Check if modified during task
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    else
        FILE_MODIFIED="false"
    fi

    # Check content for correct password
    if grep -q "GymAnything123!" "$TARGET_FILE"; then
        PASSWORD_CORRECT="true"
    else
        PASSWORD_CORRECT="false"
    fi
else
    FILE_EXISTS="false"
    FILE_PERMS="000"
    FILE_MODIFIED="false"
    PASSWORD_CORRECT="false"
fi

# 2. Functional Check (HTTP Request)
# Use curl to check if the site loads successfully
# -s: silent, -o: output to file, -w: write out HTTP code
HTTP_CODE=$(curl -s -o /tmp/http_response.txt -w "%{http_code}" "$TARGET_URL" || echo "000")
HTTP_BODY=$(cat /tmp/http_response.txt 2>/dev/null || echo "")

# Check if body contains success string
if echo "$HTTP_BODY" | grep -q "System Operational"; then
    SITE_OPERATIONAL="true"
else
    SITE_OPERATIONAL="false"
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_perms": "$FILE_PERMS",
    "file_modified": $FILE_MODIFIED,
    "password_correct": $PASSWORD_CORRECT,
    "http_code": $HTTP_CODE,
    "site_operational": $SITE_OPERATIONAL,
    "http_body_preview": "$(echo "${HTTP_BODY:0:100}" | sed 's/"/\\"/g')" 
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="