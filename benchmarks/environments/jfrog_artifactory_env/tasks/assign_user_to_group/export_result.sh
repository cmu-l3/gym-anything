#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting assign_user_to_group result ==="

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Group Info (Check if user is in group)
# Note: ?includeUsers=true is required to see members in the group object
GROUP_INFO=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/security/groups/release-engineers?includeUsers=true" 2>/dev/null || echo "{}")

# 3. Get User Info (Fallback: Check if group is in user object)
USER_INFO=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/security/users/dev-maria" 2>/dev/null || echo "{}")

# 4. Check if User Exists (Auth check fallback for OSS restrictions)
USER_AUTH_CHECK="false"
if curl -s -u "dev-maria:DevMaria2024!" "${ARTIFACTORY_URL}/artifactory/api/system/ping" | grep -q "OK"; then
    USER_AUTH_CHECK="true"
fi

# 5. Export to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "group_info": $GROUP_INFO,
    "user_info": $USER_INFO,
    "user_auth_success": $USER_AUTH_CHECK,
    "timestamp": $(date +%s),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json