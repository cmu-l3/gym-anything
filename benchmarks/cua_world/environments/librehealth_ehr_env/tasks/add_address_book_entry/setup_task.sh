#!/bin/bash
echo "=== Setting up Add Address Book Entry Task ==="

source /workspace/scripts/task_utils.sh

# Ensure LibreHealth EHR is running
wait_for_librehealth 60

# Clean state: Remove any pre-existing entry for Elena Rodriguez to ensure a clean test
echo "Cleaning up any previous entries for Elena Rodriguez..."
librehealth_query "DELETE FROM users WHERE fname='Elena' AND lname='Rodriguez'" 2>/dev/null || true

# Record initial state for anti-gaming
# We capture the maximum ID in the users table. The new entry must have an ID greater than this.
INITIAL_MAX_ID=$(librehealth_query "SELECT MAX(id) FROM users" 2>/dev/null || echo "0")
# If table is empty (unlikely), default to 0
if [ -z "$INITIAL_MAX_ID" ] || [ "$INITIAL_MAX_ID" == "NULL" ]; then
    INITIAL_MAX_ID=0
fi
echo "$INITIAL_MAX_ID" > /tmp/initial_max_user_id.txt
echo "Initial Max User ID: $INITIAL_MAX_ID"

# Record task start timestamp
date +%s > /tmp/task_start_time.txt

# Start Firefox at Login Page
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="