#!/bin/bash
echo "=== Setting up credential_leak_response task ==="

# Source utility functions for 2N Access Commander
source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Wait for the inner VM (2N Access Commander) to be reachable
wait_for_ac_demo

# Authenticate to the API
ac_login

# Record the initial state and user count
ac_api GET "/users?limit=1000" > /tmp/initial_users.json
INITIAL_COUNT=$(jq length /tmp/initial_users.json 2>/dev/null || echo "25")
echo "$INITIAL_COUNT" > /tmp/task_initial_count.txt
echo "Initial user count: $INITIAL_COUNT"

# Launch Firefox directly to the Users page
launch_firefox_to "${AC_URL}/#/users" 8

# Take initial screenshot for evidence
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="