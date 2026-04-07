#!/bin/bash
echo "=== Setting up enforce_visual_naming_conventions task ==="
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Wait for 2N Access Commander inner VM to be responsive
wait_for_ac_demo

# Authenticate via REST API to capture ground-truth initial state
echo "Recording initial system state..."
ac_login
ac_api GET "/users" > /tmp/initial_users.json
ac_api GET "/groups" > /tmp/initial_groups.json

# Ensure files are readable by the verifier export
chmod 666 /tmp/initial_users.json /tmp/initial_groups.json

# Launch Firefox directly to the Users management page
echo "Launching Firefox to Users page..."
launch_firefox_to "${AC_URL}/#/users" 8

# Capture visual proof of initial state
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="