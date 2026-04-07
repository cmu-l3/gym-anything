#!/bin/bash
set -e
echo "=== Exporting create_user_profile results ==="

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Get task start info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(cat /tmp/initial_max_profile_id.txt 2>/dev/null || echo "0")

# 1. Check if the profile exists and get its ID
# We look for a profile created with ID > INITIAL_MAX_ID to ensure it's new
PROFILE_QUERY="SELECT id, title FROM user_profiles WHERE id > $INITIAL_MAX_ID AND title LIKE '%Guidance Counselor%' LIMIT 1"
PROFILE_DATA=$(mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -B -e "$PROFILE_QUERY" 2>/dev/null || true)

PROFILE_FOUND="false"
PROFILE_ID="null"
PROFILE_TITLE=""
PERMISSIONS_JSON="[]"

if [ -n "$PROFILE_DATA" ]; then
    PROFILE_FOUND="true"
    PROFILE_ID=$(echo "$PROFILE_DATA" | cut -f1)
    PROFILE_TITLE=$(echo "$PROFILE_DATA" | cut -f2)
    
    # 2. Get permissions for this profile
    # We select modname, can_use, can_edit for analysis
    # Using python to format SQL output as JSON directly to avoid parsing issues
    PERMISSIONS_QUERY="SELECT modname, can_use, can_edit FROM profile_exceptions WHERE profile_id = $PROFILE_ID"
    
    # Export permissions to a temp file
    mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -B -e "$PERMISSIONS_QUERY" > /tmp/perms_raw.txt 2>/dev/null || true
    
    # Convert tab-separated perms to JSON
    PERMISSIONS_JSON=$(python3 -c '
import json
import sys
perms = []
try:
    with open("/tmp/perms_raw.txt", "r") as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) >= 3:
                perms.append({
                    "modname": parts[0],
                    "can_use": parts[1],
                    "can_edit": parts[2]
                })
except FileNotFoundError:
    pass
print(json.dumps(perms))
')
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "profile_found": $PROFILE_FOUND,
    "profile_id": $PROFILE_ID,
    "profile_title": "$PROFILE_TITLE",
    "permissions": $PERMISSIONS_JSON,
    "initial_max_id": $INITIAL_MAX_ID
}
EOF

# Move to standard location with lenient permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json