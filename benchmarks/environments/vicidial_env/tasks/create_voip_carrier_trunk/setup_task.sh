#!/bin/bash
set -e
echo "=== Setting up create_voip_carrier_trunk task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Vicidial is running
vicidial_ensure_running

# 1. Clean environment: Remove the carrier if it already exists
echo "Cleaning pre-existing FLOWRT01 carrier if any..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "DELETE FROM vicidial_server_carriers WHERE carrier_id='FLOWRT01';" \
  2>/dev/null || true

# 2. Record initial state
# Get the active server IP (the one the agent needs to find)
SERVER_IP=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT server_ip FROM servers WHERE active='Y' LIMIT 1;" 2>/dev/null || echo "")
echo "$SERVER_IP" > /tmp/vicidial_active_server_ip.txt
echo "Active server IP identified as: $SERVER_IP"

# Record initial count of carriers
INITIAL_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e \
  "SELECT COUNT(*) FROM vicidial_server_carriers;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_carrier_count.txt

# 3. Prepare Application (Firefox)
# Kill any existing firefox
pkill -f firefox 2>/dev/null || true
sleep 1

# Launch Firefox to Vicidial Admin
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/vicidial/admin.php' > /tmp/firefox_vicidial.log 2>&1 &"

# Wait for window
wait_for_window "firefox\|mozilla\|vicidial" 30

# Maximize and focus
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i 'firefox\|mozilla\|vicidial' | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any potential "Restore Session" dialogs by pressing Escape
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="