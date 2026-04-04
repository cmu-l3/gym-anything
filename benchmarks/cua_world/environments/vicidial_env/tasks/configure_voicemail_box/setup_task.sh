#!/bin/bash
set -e

echo "=== Setting up Configure Voicemail Box task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Vicidial is running
vicidial_ensure_running

# 3. Clean state: Remove voicemail 8500 if it exists to ensure a clean start
echo "Cleaning up any existing voicemail 8500..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_voicemail WHERE voicemail_id='8500';" 2>/dev/null || true

# 4. Prepare Firefox
# Kill existing Firefox to ensure clean state
pkill -f firefox 2>/dev/null || true

# Launch Firefox and navigate to Admin URL
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox '${VICIDIAL_ADMIN_URL}' > /dev/null 2>&1 &"

# Wait for window
wait_for_window "Firefox" 30

# Focus and maximize
focus_firefox
maximize_active_window

# Handle Login if redirected to login page (Basic Auth handled by URL often, but just in case of form auth)
# The default environment setup usually handles Basic Auth or pre-auth. 
# We'll assume the agent lands on the Admin page or Login page.

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot "/tmp/task_initial.png"

echo "=== Task setup complete ==="