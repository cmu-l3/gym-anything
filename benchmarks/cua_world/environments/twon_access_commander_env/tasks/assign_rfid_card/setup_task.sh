#!/bin/bash
echo "=== Setting up assign_rfid_card task ==="
source /workspace/scripts/task_utils.sh

wait_for_ac_demo
ac_login

# Delete any prior Derek Caldwell user
EXISTING=$(ac_api GET "/users" | jq -r '.[] | select(.firstName=="Derek" and .lastName=="Caldwell") | .id' 2>/dev/null)
for uid in $EXISTING; do
    ac_api DELETE "/users/$uid" > /dev/null 2>&1 && echo "Deleted prior Derek Caldwell" || true
done

# Create Derek Caldwell with no credentials yet
echo "Creating Derek Caldwell..."
CREATE_RESP=$(ac_api POST "/users" '{"firstName":"Derek","lastName":"Caldwell","email":"derek.caldwell@example.com","company":"Gateway Corp","enabled":true}')
USER_ID=$(echo "$CREATE_RESP" | jq -r '.id // .userId // empty' 2>/dev/null)
echo "Created user Derek Caldwell, id=$USER_ID"

# Save user ID for verifier
echo "$USER_ID" > /tmp/task_derek_caldwell_id.txt

# Navigate to Derek's user profile
if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
    launch_firefox_to "${AC_URL}/#/users/${USER_ID}" 8
else
    launch_firefox_to "${AC_URL}/#/users" 8
fi

take_screenshot /tmp/task_assign_rfid_card_start.png
echo "=== Task assign_rfid_card setup complete ==="
