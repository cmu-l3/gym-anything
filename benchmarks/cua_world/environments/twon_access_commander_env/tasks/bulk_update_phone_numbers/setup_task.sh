#!/bin/bash
echo "=== Setting up bulk_update_phone_numbers task ==="

source /workspace/scripts/task_utils.sh

# Wait for Access Commander inner VM to be reachable
wait_for_ac_demo

# Authenticate to the API
ac_login

# Fetch and record the initial state of all users
echo "Fetching initial user records..."
ac_api GET "/users" > /tmp/initial_users.json 2>/dev/null

# Validate that we successfully fetched users
if ! grep -q "firstName" /tmp/initial_users.json; then
    echo "WARNING: Failed to fetch users on first try. Retrying in 5s..."
    sleep 5
    ac_login
    ac_api GET "/users" > /tmp/initial_users.json 2>/dev/null
fi

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Launch Firefox and navigate directly to the Users section
echo "Launching Firefox..."
launch_firefox_to "${AC_URL}/#/users" 8

# Take screenshot of the initial state
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="