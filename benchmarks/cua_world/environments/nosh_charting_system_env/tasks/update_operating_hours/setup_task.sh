#!/bin/bash
# Setup script for update_operating_hours task
# Goal: Ensure NOSH is running, reset Friday hours to standard 5pm close, and prep browser.

set -e
echo "=== Setting up update_operating_hours task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Reset Database State
# Ensure Friday close is set to 17:00 (5 PM) initially so we can detect the change to 13:00
echo "Resetting practice schedule to standard hours..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "UPDATE practiceinfo SET fri_c='17:00', mon_c='17:00', fri_o='08:00' WHERE practice_id=1;" 2>/dev/null

# 3. Record Initial State for verification comparison
# We record the specific fields we care about
INITIAL_STATE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT fri_c, mon_c, fri_o FROM practiceinfo WHERE practice_id=1;" 2>/dev/null)
echo "$INITIAL_STATE" > /tmp/initial_schedule_state.txt
echo "Initial DB State (Fri Close, Mon Close, Fri Open): $INITIAL_STATE"

# 4. Prepare Browser (Firefox)
# Kill any existing instances to ensure clean state
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Clean up lock files that might prevent startup
find /home/ga/.mozilla/firefox -name ".parentlock" -delete 2>/dev/null || true
find /home/ga/.mozilla/firefox -name "lock" -delete 2>/dev/null || true
find /home/ga/snap/firefox/common/.mozilla/firefox -name ".parentlock" -delete 2>/dev/null || true

# Launch Firefox to Login Page
echo "Launching Firefox..."
NOSH_URL="http://localhost/login"

if snap list firefox &>/dev/null 2>&1; then
    # Snap Firefox
    FF_CMD="/snap/bin/firefox"
else
    # Native Firefox
    FF_CMD="firefox"
fi

su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid $FF_CMD --new-instance '$NOSH_URL' > /dev/null 2>&1 &"

# Wait for window
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|nosh"; then
        echo "Firefox window detected."
        break
    fi
    sleep 1
done

# Maximize Window
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus Window
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 5. Capture Initial Screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="