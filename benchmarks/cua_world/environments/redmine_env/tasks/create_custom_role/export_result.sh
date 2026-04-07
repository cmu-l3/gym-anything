#!/bin/bash
echo "=== Exporting create_custom_role results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get API Key to query Redmine
API_KEY=$(redmine_admin_api_key)
if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
    echo "WARNING: Admin API key not found. Trying to fetch public data or using DB fallback."
fi

# 3. Fetch Roles from Redmine API
# We need to find the ID of "External Auditor" first, then get its details
ROLES_JSON="/tmp/roles_list.json"
ROLE_DETAILS_JSON="/tmp/role_details.json"

curl -s -H "X-Redmine-API-Key: $API_KEY" "$REDMINE_BASE_URL/roles.json" > "$ROLES_JSON"

# Extract ID for "External Auditor"
ROLE_ID=$(jq -r '.roles[] | select(.name == "External Auditor") | .id' "$ROLES_JSON" 2>/dev/null || echo "")

ROLE_FOUND="false"
PERMISSIONS_LIST="[]"

if [ -n "$ROLE_ID" ] && [ "$ROLE_ID" != "null" ]; then
    ROLE_FOUND="true"
    # Fetch details for this specific role to see permissions
    curl -s -H "X-Redmine-API-Key: $API_KEY" "$REDMINE_BASE_URL/roles/$ROLE_ID.json" > "$ROLE_DETAILS_JSON"
    PERMISSIONS_LIST=$(jq '.role.permissions' "$ROLE_DETAILS_JSON" 2>/dev/null || echo "[]")
else
    echo "Role 'External Auditor' not found via API."
fi

# 4. Check file timestamps (anti-gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 5. Construct Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "role_found": $ROLE_FOUND,
    "role_name": "External Auditor",
    "permissions": $PERMISSIONS_LIST,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json