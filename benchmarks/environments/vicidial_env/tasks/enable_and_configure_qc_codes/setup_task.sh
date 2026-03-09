#!/bin/bash
set -e
echo "=== Setting up Enable and Configure QC Codes task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial container is running
vicidial_ensure_running

echo "Resetting Vicidial state for task..."

# 1. Disable QC Features in System Settings (to ensure agent has to enable it)
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "UPDATE system_settings SET qc_features_active='0';"

# 2. Delete the specific codes we expect the agent to create (to ensure they are new)
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_qc_codes WHERE code IN ('PCI_FAIL', 'RUDE', 'EXCELLENT');"

echo "State reset complete."

# 3. Launch Firefox and login to Admin panel
# We use the generic 6666/andromeda credentials
VICIDIAL_ADMIN_URL="http://localhost/vicidial/admin.php"

# Kill existing firefox instances
pkill -f firefox 2>/dev/null || true

# Start Firefox
su - ga -c "DISPLAY=:1 firefox '${VICIDIAL_ADMIN_URL}' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 60

# Maximize and focus
focus_firefox
maximize_active_window

# Handle HTTP Basic Auth if it appears (common in some Vicidial setups)
# OR Handle the Vicidial Login Form
echo "Handling login..."
sleep 5
# Type username
DISPLAY=:1 xdotool type --delay 50 "6666"
DISPLAY=:1 xdotool key Tab
# Type password
DISPLAY=:1 xdotool type --delay 50 "andromeda"
DISPLAY=:1 xdotool key Return

sleep 5

# Navigate explicitly to Admin main page to start
navigate_to_url "http://localhost/vicidial/admin.php"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="