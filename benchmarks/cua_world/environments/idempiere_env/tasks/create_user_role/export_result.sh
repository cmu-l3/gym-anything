#!/bin/bash
set -e
echo "=== Exporting create_user_role task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_emily_count.txt 2>/dev/null || echo "0")
CLIENT_ID=11

# Take final screenshot
take_screenshot /tmp/task_final.png

echo "--- Querying iDempiere Database ---"

# We query for the user 'Emily Clark' created most recently
# We fetch all relevant fields to verify criteria in the python verifier
# Using COALESCE to handle NULLs for JSON safety
USER_JSON=$(idempiere_query "
SELECT row_to_json(t) FROM (
    SELECT 
        u.ad_user_id,
        u.name,
        u.email,
        u.isactive,
        COALESCE(u.isloginuser, 'N') as isloginuser,
        CASE WHEN u.password IS NOT NULL THEN 'Y' ELSE 'N' END as has_password,
        EXTRACT(EPOCH FROM u.created)::bigint as created_ts,
        (
            SELECT COUNT(*) 
            FROM ad_user_roles ur 
            JOIN ad_role r ON ur.ad_role_id = r.ad_role_id 
            WHERE ur.ad_user_id = u.ad_user_id 
            AND r.name = 'GardenWorld Admin'
            AND ur.isactive = 'Y'
        ) as role_assigned_count
    FROM ad_user u
    WHERE u.name = 'Emily Clark' 
    AND u.ad_client_id = $CLIENT_ID
    ORDER BY u.created DESC
    LIMIT 1
) t;
" 2>/dev/null || echo "")

# If no user found, provide a default empty object structure
if [ -z "$USER_JSON" ]; then
    echo "User 'Emily Clark' not found in database."
    USER_JSON="null"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_user_count": $INITIAL_COUNT,
    "user_data": $USER_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="