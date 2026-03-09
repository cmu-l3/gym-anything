#!/bin/bash
set -e
echo "=== Setting up task: Configure Inbound Queue Hold ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial services are running
vicidial_ensure_running

# Clean up any previous state (Delete SUPPORT group if it exists)
echo "Cleaning up previous 'SUPPORT' inbound group..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_inbound_groups WHERE group_id='SUPPORT';" 2>/dev/null || true

# Verify clean state
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT count(*) FROM vicidial_inbound_groups WHERE group_id='SUPPORT';" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial SUPPORT group count: $INITIAL_COUNT"

# Prepare Firefox
# Kill existing instances to ensure clean start
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to Admin interface
# Note: Using credentials in URL to handle basic auth if configured, though Vicidial often uses form auth
VICIDIAL_URL="http://localhost/vicidial/admin.php"

echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox '$VICIDIAL_URL' > /dev/null 2>&1 &"

# Wait for window
wait_for_window "Firefox" 30

# Focus and maximize
focus_firefox
maximize_active_window

# Handle potential Basic Auth dialog or Login Form
# We'll just ensure the window is focused; the agent is expected to handle login if needed
# based on the task description, but we can try to pre-fill if it's the standard form.
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="