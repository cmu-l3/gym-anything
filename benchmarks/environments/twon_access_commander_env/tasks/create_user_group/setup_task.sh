#!/bin/bash
echo "=== Setting up create_user_group task ==="
source /workspace/scripts/task_utils.sh

wait_for_ac_demo
ac_login

# Clean up any prior 'Maintenance Staff' group
EXISTING=$(ac_api GET "/groups" | jq -r '.[] | select(.name=="Maintenance Staff") | .id' 2>/dev/null)
for gid in $EXISTING; do
    ac_api DELETE "/groups/$gid" > /dev/null 2>&1 && echo "Deleted prior Maintenance Staff group" || true
done

# Navigate to Groups page
launch_firefox_to "${AC_URL}/#/groups" 8

take_screenshot /tmp/task_create_user_group_start.png
echo "=== Task create_user_group setup complete ==="
