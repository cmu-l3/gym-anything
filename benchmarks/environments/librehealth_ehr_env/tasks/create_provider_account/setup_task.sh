#!/bin/bash
set -e
echo "=== Setting up task: Create Provider Account ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure LibreHealth EHR is accessible
wait_for_librehealth 120

# --- Clean Slate Setup ---
# Remove the user 'schen' if it already exists to ensure the agent actually creates it
echo "Cleaning up any pre-existing 'schen' user..."
librehealth_query "DELETE FROM users_secure WHERE username='schen'" 2>/dev/null || true
librehealth_query "DELETE FROM users WHERE username='schen'" 2>/dev/null || true

# Record initial user count for anti-gaming detection
INITIAL_USER_COUNT=$(librehealth_query "SELECT COUNT(*) FROM users" 2>/dev/null || echo "0")
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count.txt
echo "Initial user count: $INITIAL_USER_COUNT"

# Restart Firefox at the login page
# We use the generic login page
restart_firefox "http://localhost:8000/interface/login/login.php?site=default"

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="