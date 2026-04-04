#!/bin/bash
set -e

echo "=== Setting up Configure Callback Compliance task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure Vicidial is running
vicidial_ensure_running

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up environment: Ensure campaign CB_SAFE does not exist
echo "Cleaning up any existing CB_SAFE campaign..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_campaigns WHERE campaign_id='CB_SAFE';" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_campaign_stats WHERE campaign_id='CB_SAFE';" 2>/dev/null || true

# Launch Firefox and login
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true

# Start Firefox pointing to Admin
su - ga -c "DISPLAY=:1 firefox '${VICIDIAL_ADMIN_URL}' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 30

# Focus and maximize
focus_firefox
maximize_active_window

# Handle Login if needed (though session might persist, it's safer to type it if on login screen)
# We assume the standard Basic Auth or Form might appear. 
# The env setup usually handles Basic Auth via URL or user interaction.
# If stuck on Basic Auth prompt, the agent needs to handle it, but we can try to pre-fill if it's a form.
# Given the env description, it likely uses Basic Auth or a form. 
# We'll just ensure the window is ready.

sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="