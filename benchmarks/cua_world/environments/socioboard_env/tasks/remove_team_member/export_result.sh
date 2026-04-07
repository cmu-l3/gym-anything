#!/bin/bash
echo "=== Exporting remove_team_member task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TEAM_NAME="Content Creators"
TAYLOR_EMAIL="taylor@socioboard.local"
ADMIN_EMAIL="admin@socioboard.local"

# Verify if team exists
TEAM_EXISTS_COUNT=$(mysql -u root "$DB_NAME" -N -e "SELECT COUNT(*) FROM team_informations WHERE team_name = '${TEAM_NAME}'" 2>/dev/null || echo "0")

TEAM_EXISTS="false"
TAYLOR_IN_TEAM="false"
ADMIN_IN_TEAM="false"
MEMBER_COUNT=0

if [ "$TEAM_EXISTS_COUNT" -gt 0 ]; then
    TEAM_EXISTS="true"
    
    TEAM_ID=$(mysql -u root "$DB_NAME" -N -e "SELECT team_id FROM team_informations WHERE team_name = '${TEAM_NAME}' LIMIT 1" 2>/dev/null)
    TAYLOR_ID=$(mysql -u root "$DB_NAME" -N -e "SELECT user_id FROM user_details WHERE email = '${TAYLOR_EMAIL}' LIMIT 1" 2>/dev/null)
    ADMIN_ID=$(mysql -u root "$DB_NAME" -N -e "SELECT user_id FROM user_details WHERE email = '${ADMIN_EMAIL}' LIMIT 1" 2>/dev/null)
    
    if [ -n "$TEAM_ID" ] && [ -n "$TAYLOR_ID" ]; then
        # Check if Taylor is still an active member (Socioboard uses left_team=1 for removed members)
        TAYLOR_STATUS=$(mysql -u root "$DB_NAME" -N -e "SELECT left_team FROM join_table_users_teams WHERE team_id = '$TEAM_ID' AND user_id = '$TAYLOR_ID' ORDER BY id DESC LIMIT 1" 2>/dev/null)
        if [ "$TAYLOR_STATUS" = "0" ]; then
            TAYLOR_IN_TEAM="true"
        fi
    fi
    
    if [ -n "$TEAM_ID" ] && [ -n "$ADMIN_ID" ]; then
        ADMIN_STATUS=$(mysql -u root "$DB_NAME" -N -e "SELECT left_team FROM join_table_users_teams WHERE team_id = '$TEAM_ID' AND user_id = '$ADMIN_ID' ORDER BY id DESC LIMIT 1" 2>/dev/null)
        if [ "$ADMIN_STATUS" = "0" ]; then
            ADMIN_IN_TEAM="true"
        fi
    fi
    
    # Get total active member count
    MEMBER_COUNT=$(mysql -u root "$DB_NAME" -N -e "SELECT COUNT(*) FROM join_table_users_teams WHERE team_id = '$TEAM_ID' AND left_team = 0" 2>/dev/null || echo "0")
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "team_exists": $TEAM_EXISTS,
    "taylor_in_team": $TAYLOR_IN_TEAM,
    "admin_in_team": $ADMIN_IN_TEAM,
    "member_count": $MEMBER_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safely move JSON
rm -f /tmp/remove_team_member_result.json 2>/dev/null || sudo rm -f /tmp/remove_team_member_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/remove_team_member_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/remove_team_member_result.json
chmod 666 /tmp/remove_team_member_result.json 2>/dev/null || sudo chmod 666 /tmp/remove_team_member_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/remove_team_member_result.json"
cat /tmp/remove_team_member_result.json