#!/bin/bash
echo "=== Setting up add_user_to_group task ==="
source /workspace/scripts/task_utils.sh

wait_for_ac_demo
ac_login

# Clean up prior Sandra Okafor
EXISTING_USERS=$(ac_api GET "/users" | jq -r '.[] | select(.firstName=="Sandra" and .lastName=="Okafor") | .id' 2>/dev/null)
for uid in $EXISTING_USERS; do
    ac_api DELETE "/users/$uid" > /dev/null 2>&1 && echo "Deleted prior Sandra Okafor" || true
done

# Clean up prior Reception Team group
EXISTING_GROUPS=$(ac_api GET "/groups" | jq -r '.[] | select(.name=="Reception Team") | .id' 2>/dev/null)
for gid in $EXISTING_GROUPS; do
    ac_api DELETE "/groups/$gid" > /dev/null 2>&1 && echo "Deleted prior Reception Team group" || true
done

# Create Sandra Okafor
echo "Creating Sandra Okafor..."
USER_RESP=$(ac_api POST "/users" '{"firstName":"Sandra","lastName":"Okafor","email":"sandra.okafor@example.com","company":"Concierge Services","enabled":true}')
USER_ID=$(echo "$USER_RESP" | jq -r '.id // .userId // empty' 2>/dev/null)
echo "Created Sandra Okafor id=$USER_ID"
echo "$USER_ID" > /tmp/task_sandra_okafor_id.txt

# Create Reception Team group
echo "Creating Reception Team group..."
GRP_RESP=$(ac_api POST "/groups" '{"name":"Reception Team","description":"Front desk and reception staff"}')
GROUP_ID=$(echo "$GRP_RESP" | jq -r '.id // .groupId // empty' 2>/dev/null)
echo "Created Reception Team group id=$GROUP_ID"
echo "$GROUP_ID" > /tmp/task_reception_team_id.txt

# Navigate to Sandra's user profile
if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
    launch_firefox_to "${AC_URL}/#/users/${USER_ID}" 8
else
    launch_firefox_to "${AC_URL}/#/users" 8
fi

take_screenshot /tmp/task_add_user_to_group_start.png
echo "=== Task add_user_to_group setup complete ==="
