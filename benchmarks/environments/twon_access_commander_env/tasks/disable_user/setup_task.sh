#!/bin/bash
echo "=== Setting up disable_user task ==="
source /workspace/scripts/task_utils.sh

wait_for_ac_demo
ac_login

# Clean up prior Victor Schulz
EXISTING=$(ac_api GET "/users" | jq -r '.[] | select(.firstName=="Victor" and .lastName=="Schulz") | .id' 2>/dev/null)
for uid in $EXISTING; do
    ac_api DELETE "/users/$uid" > /dev/null 2>&1 && echo "Deleted prior Victor Schulz" || true
done

# Create Victor Schulz as an ACTIVE user
echo "Creating Victor Schulz (enabled=true)..."
USER_RESP=$(ac_api POST "/users" '{"firstName":"Victor","lastName":"Schulz","email":"victor.schulz@example.com","company":"Eastern Security","enabled":true}')
USER_ID=$(echo "$USER_RESP" | jq -r '.id // .userId // empty' 2>/dev/null)
echo "Created Victor Schulz id=$USER_ID (active)"
echo "$USER_ID" > /tmp/task_victor_schulz_id.txt

# Navigate to Victor's profile
if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
    launch_firefox_to "${AC_URL}/#/users/${USER_ID}" 8
else
    launch_firefox_to "${AC_URL}/#/users" 8
fi

take_screenshot /tmp/task_disable_user_start.png
echo "=== Task disable_user setup complete ==="
