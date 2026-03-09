#!/bin/bash
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

TARGET_USER="alex_rookie"
TARGET_GROUP="FOIA_Processors"
LDAP_POD="arkcase-ldap-0"
NS="arkcase"

# Record Task End
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Verification via LDAP (Primary Signal)
echo "Checking LDAP membership..."
LDAP_MEMBERS=$(kubectl exec -n "$NS" "$LDAP_POD" -- samba-tool group members "$TARGET_GROUP" 2>/dev/null || echo "")
echo "Group members: $LDAP_MEMBERS"

if echo "$LDAP_MEMBERS" | grep -q "$TARGET_USER"; then
    LDAP_CONFIRMED="true"
    echo "SUCCESS: User found in LDAP group."
else
    LDAP_CONFIRMED="false"
    echo "FAILURE: User not found in LDAP group."
fi

# 2. Verification via ArkCase API (Secondary Signal)
# This checks if the application layer sees the membership
echo "Checking ArkCase API..."
# Endpoint to get user details including groups
# Note: Endpoint path might vary by ArkCase version, trying common path
API_RESPONSE=$(arkcase_api GET "users/$TARGET_USER" 2>/dev/null || echo "")

# Simple string check on JSON response for the group name
if echo "$API_RESPONSE" | grep -q "$TARGET_GROUP"; then
    API_CONFIRMED="true"
    echo "SUCCESS: Group found in User API response."
else
    API_CONFIRMED="false"
    echo "FAILURE: Group not found in User API response."
fi

# 3. Check User Existence (Anti-Corruption)
USER_EXISTS="false"
if kubectl exec -n "$NS" "$LDAP_POD" -- samba-tool user show "$TARGET_USER" >/dev/null 2>&1; then
    USER_EXISTS="true"
fi

# 4. App Status
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# 5. Final Screenshot
take_screenshot /tmp/task_final.png

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "ldap_confirmed": $LDAP_CONFIRMED,
    "api_confirmed": $API_CONFIRMED,
    "user_exists": $USER_EXISTS,
    "app_running": $APP_RUNNING,
    "target_user": "$TARGET_USER",
    "target_group": "$TARGET_GROUP",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="