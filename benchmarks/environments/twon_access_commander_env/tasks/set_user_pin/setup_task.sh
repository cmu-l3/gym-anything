#!/bin/bash
echo "=== Setting up set_user_pin task ==="
source /workspace/scripts/task_utils.sh

wait_for_ac_demo
ac_login

# Clean up prior Marcus Webb
EXISTING=$(ac_api GET "/users" | jq -r '.[] | select(.firstName=="Marcus" and .lastName=="Webb") | .id' 2>/dev/null)
for uid in $EXISTING; do
    ac_api DELETE "/users/$uid" > /dev/null 2>&1 && echo "Deleted prior Marcus Webb" || true
done

# Create Marcus Webb (no credentials yet)
echo "Creating Marcus Webb..."
USER_RESP=$(ac_api POST "/users" '{"firstName":"Marcus","lastName":"Webb","email":"marcus.webb@example.com","company":"Logistics Ltd","enabled":true}')
USER_ID=$(echo "$USER_RESP" | jq -r '.id // .userId // empty' 2>/dev/null)
echo "Created Marcus Webb id=$USER_ID"
echo "$USER_ID" > /tmp/task_marcus_webb_id.txt

# Navigate to Marcus's profile
if [ -n "$USER_ID" ] && [ "$USER_ID" != "null" ]; then
    launch_firefox_to "${AC_URL}/#/users/${USER_ID}" 8
else
    launch_firefox_to "${AC_URL}/#/users" 8
fi

take_screenshot /tmp/task_set_user_pin_start.png
echo "=== Task set_user_pin setup complete ==="
