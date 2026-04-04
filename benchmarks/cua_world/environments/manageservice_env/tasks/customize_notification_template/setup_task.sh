#!/bin/bash
# Setup script for customize_notification_template

echo "=== Setting up Customize Notification Template task ==="
source /workspace/scripts/task_utils.sh

# 1. Ensure SDP is running
ensure_sdp_running

# 2. Clean state: Remove any previous modifications to notifications
# This prevents false positives if the environment wasn't reset
echo "Resetting notification templates to clean state..."
# Attempt to revert changes where subject matches task specific strings
sdp_db_exec "UPDATE notificationtemplate SET subject = 'Request received : \$RequestId', message = 'The request has been received.' WHERE subject LIKE '%Global Corp%' OR message LIKE '%555-0199%';" 2>/dev/null || true

# 3. Open Firefox to the Admin page (saves agent some clicks, sets context)
# We navigate to the Admin tab to give a helpful starting point
log "Opening Firefox to Admin console..."
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Admin.do"
sleep 5

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

# 5. Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Setup complete ==="