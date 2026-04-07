#!/bin/bash
echo "=== Exporting resolve_credential_conflict result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot evidence
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Authenticate via REST API for state extraction
ac_login

# Fetch all users
USERS_JSON=$(ac_api GET "/users" 2>/dev/null || echo "[]")

# Extract IDs of the original holder and the new hire
DEREK_ID=$(echo "$USERS_JSON" | jq -r '.[] | select(.firstName=="Derek" and .lastName=="Caldwell") | .id' 2>/dev/null)
SAMUEL_ID=$(echo "$USERS_JSON" | jq -r '.[] | select(.firstName=="Samuel" and .lastName=="Jenkins") | .id' 2>/dev/null)

DEREK_FULL="{}"
if [ -n "$DEREK_ID" ] && [ "$DEREK_ID" != "null" ]; then
    DEREK_FULL=$(ac_api GET "/users/$DEREK_ID" 2>/dev/null || echo "{}")
fi

SAMUEL_FULL="{}"
if [ -n "$SAMUEL_ID" ] && [ "$SAMUEL_ID" != "null" ]; then
    SAMUEL_FULL=$(ac_api GET "/users/$SAMUEL_ID" 2>/dev/null || echo "{}")
fi

# Write results to JSON for the Python verifier
TEMP_JSON=$(mktemp)
cat <<EOF > "$TEMP_JSON"
{
   "derek_exists": $(if [ -n "$DEREK_ID" ] && [ "$DEREK_ID" != "null" ]; then echo "true"; else echo "false"; fi),
   "samuel_exists": $(if [ -n "$SAMUEL_ID" ] && [ "$SAMUEL_ID" != "null" ]; then echo "true"; else echo "false"; fi),
   "derek_data": $DEREK_FULL,
   "samuel_data": $SAMUEL_FULL,
   "task_end_time": $(date +%s)
}
EOF

# Safely move into place with permissive permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result payload successfully extracted to /tmp/task_result.json"
echo "=== Export complete ==="