#!/bin/bash
echo "=== Setting up update_user_email task ==="
source /workspace/scripts/task_utils.sh

wait_for_ac_demo
ac_login

# Clean up prior Priya Nair
EXISTING=$(ac_api GET "/users" | jq -r '.[] | select(.firstName=="Priya" and .lastName=="Nair") | .id' 2>/dev/null)
for uid in $EXISTING; do
    ac_api DELETE "/users/$uid" > /dev/null 2>&1 && echo "Deleted prior Priya Nair" || true
done

# Create Priya Nair with initial email (to be updated)
echo "Creating Priya Nair..."
USER_RESP=$(ac_api POST "/users" '{"firstName":"Priya","lastName":"Nair","email":"priya.nair@oldcompany.com","company":"Old Company Inc","enabled":true}')
USER_ID=$(echo "$USER_RESP" | jq -r '.id // .userId // empty' 2>/dev/null)
echo "Created Priya Nair id=$USER_ID (email=priya.nair@oldcompany.com)"
echo "$USER_ID" > /tmp/task_priya_nair_id.txt

# Navigate to Priya's profile
if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
    launch_firefox_to "${AC_URL}/#/users/${USER_ID}" 8
else
    launch_firefox_to "${AC_URL}/#/users" 8
fi

take_screenshot /tmp/task_update_user_email_start.png
echo "=== Task update_user_email setup complete ==="
