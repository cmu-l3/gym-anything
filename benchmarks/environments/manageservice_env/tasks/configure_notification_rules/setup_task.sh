#!/bin/bash
# Setup for "configure_notification_rules" task
echo "=== Setting up Configure Notification Rules task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Ensure ServiceDesk Plus is running
ensure_sdp_running

# 2. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Capture Initial Database State (Baseline)
# We dump the NotificationRule table to see what the defaults are
echo "Recording initial database state..."
# Try to get raw dump of notification rules
# Note: Table names might vary by SDP version, trying standard ones
sdp_db_exec "SELECT * FROM NotificationRule;" > /tmp/initial_notification_rules.txt 2>/dev/null || \
sdp_db_exec "SELECT * FROM notification_rules;" > /tmp/initial_notification_rules.txt 2>/dev/null || \
echo "Could not dump notification rules" > /tmp/initial_notification_rules.txt

# 4. Launch Firefox
# Navigate directly to login page
echo "Launching Firefox..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# 5. Capture Initial Screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task Setup Complete ==="
echo "SDP is running. Agent should log in and configure notification rules."