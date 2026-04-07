#!/bin/bash
echo "=== Exporting create_user_account results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract Data via REST API
# We fetch the actual state of the system to compare against expectations in verifier.py

# A. User Data
echo "Fetching user data..."
USER_JSON=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/user/mwilson")
USER_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/user/mwilson")

# B. Workspace Data
echo "Fetching workspace data..."
WS_PATH="default-domain/workspaces/Maria-Wilson-Files"
WORKSPACE_JSON=$(curl -s -u "$NUXEO_AUTH" -H "X-NXproperties: *" "$NUXEO_URL/api/v1/path/$WS_PATH")
WORKSPACE_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/$WS_PATH")

# C. Permissions Data (ACL)
# We need to check if 'mwilson' has ReadWrite permission on the workspace
PERMISSIONS_JSON="{}"
if [ "$WORKSPACE_HTTP_CODE" = "200" ]; then
    echo "Fetching permissions..."
    PERMISSIONS_JSON=$(curl -s -u "$NUXEO_AUTH" "$NUXEO_URL/api/v1/path/$WS_PATH/@acl")
fi

# 3. Create Result JSON
# We construct a composite JSON file containing all the fetched data and metadata
RESULT_FILE="/tmp/task_result.json"
cat > "$RESULT_FILE" << EOF
{
  "timestamp": {
    "start": $TASK_START,
    "end": $TASK_END
  },
  "user": {
    "exists": $( [ "$USER_HTTP_CODE" = "200" ] && echo "true" || echo "false" ),
    "http_code": $USER_HTTP_CODE,
    "data": $USER_JSON
  },
  "workspace": {
    "exists": $( [ "$WORKSPACE_HTTP_CODE" = "200" ] && echo "true" || echo "false" ),
    "http_code": $WORKSPACE_HTTP_CODE,
    "data": $WORKSPACE_JSON
  },
  "permissions": {
    "data": $PERMISSIONS_JSON
  }
}
EOF

# Ensure permissions are correct for copy_from_env
chmod 644 "$RESULT_FILE" 2>/dev/null || true

echo "Export complete. Result saved to $RESULT_FILE"