#!/bin/bash
echo "=== Setting up provision_vms_api_account task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Wait for 2N Access Commander to be ready
wait_for_ac_demo
ac_login

# Clean up any pre-existing user from previous runs with this exact name
echo "Cleaning up previous test user (if any)..."
EXISTING=$(ac_api GET "/users" | jq -r '.[] | select(.firstName=="Milestone" and .lastName=="VMS_Service") | .id' 2>/dev/null)
for uid in $EXISTING; do
    ac_api DELETE "/users/$uid" > /dev/null 2>&1 && echo "Deleted prior Milestone VMS_Service user (id=$uid)" || true
done

# Launch Firefox and point to the Users view
launch_firefox_to "${AC_URL}/#/users" 8

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task setup complete ==="