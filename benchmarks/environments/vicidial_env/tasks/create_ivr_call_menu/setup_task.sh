#!/bin/bash
set -e

echo "=== Setting up Create IVR Call Menu Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Ensure Vicidial is running
vicidial_ensure_running

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Clean Slate: Remove the menu if it already exists to ensure the agent creates it
echo "Cleaning up any existing menu with ID 'valley_health_main'..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_call_menu WHERE menu_id='valley_health_main';" 2>/dev/null || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_call_menu_options WHERE menu_id='valley_health_main';" 2>/dev/null || true

# 2. Record initial state (Call Menu count)
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SELECT COUNT(*) FROM vicidial_call_menu;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_menu_count.txt
echo "Initial Call Menu count: $INITIAL_COUNT"

# 3. Launch Firefox and login
# We use the Admin URL. The environment setup script handles the HTTP Basic Auth via URL or pre-config if needed,
# but usually Vicidial has a form login.
VICIDIAL_ADMIN_URL="${VICIDIAL_ADMIN_URL:-http://localhost/vicidial/admin.php}"

# Close any existing firefox
pkill -f firefox 2>/dev/null || true

echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox '$VICIDIAL_ADMIN_URL' > /dev/null 2>&1 &"

# Wait for Firefox
wait_for_window "firefox\|mozilla\|vicidial" 60

# Maximize
focus_firefox
maximize_active_window

# Automate Login
echo "Logging into Vicidial..."
sleep 5
# Username
DISPLAY=:1 xdotool type --delay 50 "6666"
DISPLAY=:1 xdotool key Tab
# Password
DISPLAY=:1 xdotool type --delay 50 "andromeda"
DISPLAY=:1 xdotool key Return

# Wait for login to complete
sleep 5

# Navigate to Call Menus screen (optional, but helpful to put agent in right context)
# We won't navigate deep, just ensure we are logged in.
# The agent is expected to navigate to "Call Menus".

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="