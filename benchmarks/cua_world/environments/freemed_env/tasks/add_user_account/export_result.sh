#!/bin/bash
echo "=== Exporting add_user_account result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current user count and compare
INITIAL_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(freemed_query "SELECT COUNT(*) FROM user" 2>/dev/null || echo "0")
echo "User count: initial=$INITIAL_COUNT, current=$CURRENT_COUNT"

# Query the newly created user specifically
USER_EXISTS="false"
EXISTS_CHECK=$(freemed_query "SELECT COUNT(*) FROM user WHERE username='smitchell'" 2>/dev/null || echo "0")

if [ "${EXISTS_CHECK:-0}" -gt 0 ]; then
    USER_EXISTS="true"
    # Query fields individually to avoid delimiter parsing issues
    FNAME=$(freemed_query "SELECT userfname FROM user WHERE username='smitchell' LIMIT 1" 2>/dev/null)
    LNAME=$(freemed_query "SELECT userlname FROM user WHERE username='smitchell' LIMIT 1" 2>/dev/null)
    MNAME=$(freemed_query "SELECT usermname FROM user WHERE username='smitchell' LIMIT 1" 2>/dev/null)
    UTYPE=$(freemed_query "SELECT usertype FROM user WHERE username='smitchell' LIMIT 1" 2>/dev/null)
    UDESC=$(freemed_query "SELECT userdescrip FROM user WHERE username='smitchell' LIMIT 1" 2>/dev/null)
    UPASS=$(freemed_query "SELECT userpassword FROM user WHERE username='smitchell' LIMIT 1" 2>/dev/null)
    
    echo "Found user 'smitchell'."
else
    echo "User 'smitchell' NOT found."
    FNAME=""
    LNAME=""
    MNAME=""
    UTYPE=""
    UDESC=""
    UPASS=""
fi

# Escape description field for JSON compliance
UDESC_ESCAPED=$(echo "$UDESC" | sed 's/"/\\"/g' | sed 's/\n/\\n/g' | sed 's/\r//g')

# Format into JSON (create temp file first to avoid perm issues)
TEMP_JSON=$(mktemp /tmp/add_user_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $TASK_END,
    "initial_user_count": $INITIAL_COUNT,
    "current_user_count": $CURRENT_COUNT,
    "user_exists": $USER_EXISTS,
    "user_data": {
        "username": "smitchell",
        "userfname": "$FNAME",
        "userlname": "$LNAME",
        "usermname": "$MNAME",
        "usertype": "$UTYPE",
        "userdescrip": "$UDESC_ESCAPED",
        "userpassword": "$UPASS"
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move temp file to final destination
rm -f /tmp/add_user_result.json 2>/dev/null || sudo rm -f /tmp/add_user_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/add_user_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/add_user_result.json
chmod 666 /tmp/add_user_result.json 2>/dev/null || sudo chmod 666 /tmp/add_user_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/add_user_result.json"
cat /tmp/add_user_result.json

echo "=== Export Complete ==="