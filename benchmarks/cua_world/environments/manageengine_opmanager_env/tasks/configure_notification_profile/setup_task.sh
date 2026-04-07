#!/bin/bash
echo "=== Setting up Configure Notification Profile Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify OpManager is running (with extended timeout for slow starts)
echo "Checking OpManager health..."
if ! wait_for_opmanager_ready 120; then
    echo "WARNING: OpManager may not be fully ready"
fi

# Record timestamp
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso

# Ensure Firefox is running and showing OpManager (with retry/recovery)
# NOTE: Do NOT pre-navigate to settings page here. After checkpoint restore,
# the browser session may be stale and settings page returns "Not Authorized".
# The task description tells the agent to navigate to Settings, so let them do it.
echo "Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Configure Notification Profile Task Setup Complete ==="
echo ""
echo "Task: Create a notification profile in OpManager"
echo "  Profile Name: Critical Device Alert"
echo "  Trigger: Critical severity"
echo "  Notification Type: Email"
echo "  Recipient: ops-team@company.com"
echo ""
echo "OpManager Login: admin / Admin@123"
echo "OpManager URL: $OPMANAGER_URL"
echo ""
