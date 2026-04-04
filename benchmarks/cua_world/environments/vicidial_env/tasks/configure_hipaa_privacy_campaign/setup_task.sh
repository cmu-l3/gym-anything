#!/bin/bash
set -e

echo "=== Setting up Configure HIPAA Privacy Campaign task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Vicidial services are running
vicidial_ensure_running

# 2. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Clean up the target campaign if it already exists (idempotency)
echo "Ensuring clean state for campaign HIPAA_SEC..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_campaigns WHERE campaign_id='HIPAA_SEC';" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_campaign_stats WHERE campaign_id='HIPAA_SEC';" 2>/dev/null || true

# 4. Prepare Firefox
# Kill any existing instances
pkill -f firefox 2>/dev/null || true
sleep 1

# Start Firefox pointing to the Campaigns section
# Using Basic Auth credentials in URL for convenience if supported, or rely on auto-login if session persists.
# The env setup script handles basic auth via URL usually, or we assume the agent handles the login dialog if it appears.
# We'll launch to the main admin page.
VICIDIAL_URL="http://localhost/vicidial/admin.php?ADD=10"

echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox '${VICIDIAL_URL}' > /tmp/firefox_task.log 2>&1 &"

# 5. Wait for window and maximize
wait_for_window "firefox\|mozilla\|vicidial" 60
focus_firefox
maximize_active_window

# 6. Handle Basic Auth if needed (Vicidial standard)
# We type the credentials blindly into the active window just in case the browser modal is up
sleep 2
echo "Attempting to authenticate..."
DISPLAY=:1 xdotool type --delay 20 "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type --delay 20 "andromeda"
DISPLAY=:1 xdotool key Return

# 7. Take initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="