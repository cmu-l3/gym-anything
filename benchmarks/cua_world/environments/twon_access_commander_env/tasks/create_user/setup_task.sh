#!/bin/bash
echo "=== Setting up create_user task ==="
source /workspace/scripts/task_utils.sh

wait_for_ac_demo

# Clean up any user from a previous run with this exact name
echo "Cleaning up previous test user (if any)..."
ac_login
EXISTING=$(ac_api GET "/users" | jq -r '.[] | select(.firstName=="Heather" and .lastName=="Morrison") | .id' 2>/dev/null)
for uid in $EXISTING; do
    ac_api DELETE "/users/$uid" > /dev/null 2>&1 && echo "Deleted prior Heather Morrison (id=$uid)" || true
done

# Navigate Firefox to Users page
launch_firefox_to "${AC_URL}/#/users" 8

take_screenshot /tmp/task_create_user_start.png
echo "=== Task create_user setup complete ==="
