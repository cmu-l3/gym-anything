#!/bin/bash
echo "=== Exporting correct_inverted_names result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot for trajectory
take_screenshot /tmp/task_final.png ga

# Log in and fetch the current user state
ac_login
USERS_JSON=$(ac_api GET "/users")

CURRENT_COUNT=$(echo "$USERS_JSON" | jq '. | length' 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")

# Helper to safely extract user data by their immutable email address
get_user_info() {
    local email="$1"
    echo "$USERS_JSON" | jq -c "map(select(.email==\"$email\")) | if length > 0 then .[0] | {firstName, lastName, email} else {} end" 2>/dev/null || echo "{}"
}

USER1=$(get_user_info "s.okafor@buildingtech.com")
USER2=$(get_user_info "m.webb@buildingtech.com")
USER3=$(get_user_info "m.zhang@buildingtech.com")

# Output to temporary JSON file
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "initial_user_count": $INITIAL_COUNT,
    "current_user_count": $CURRENT_COUNT,
    "user1": $USER1,
    "user2": $USER2,
    "user3": $USER3
}
EOF

# Move to final destination safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="