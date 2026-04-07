#!/bin/bash
# Setup task: block_provider_schedule
# Goal: Ensure clean state for Dr. Carter's schedule today at 13:00

echo "=== Setting up block_provider_schedule task ==="

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Clean up any existing schedule entries for Provider 2 (James Carter) on CURDATE() around 13:00
#    This prevents the agent from claiming credit for an existing entry.
echo "Cleaning existing schedule entries..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM schedule WHERE provider_id=2 AND date=CURDATE() AND start_time >= '12:00:00' AND start_time <= '14:00:00';" 2>/dev/null || true

# 3. Ensure Firefox is fresh and ready at login
pkill -9 -f firefox 2>/dev/null || true
sleep 3

# Cleanup Firefox locks to prevent "Firefox is already running" errors
FF_SNAP="/home/ga/snap/firefox/common/.mozilla/firefox"
FF_NATIVE="/home/ga/.mozilla/firefox"
for profile_dir in "$FF_SNAP" "$FF_NATIVE"; do
    if [ -d "$profile_dir" ]; then
        find "$profile_dir" -name ".parentlock" -delete 2>/dev/null || true
        find "$profile_dir" -name "lock" -delete 2>/dev/null || true
    fi
done

# Fix permissions
chown -R ga:ga /home/ga/snap 2>/dev/null || true
chown -R ga:ga /home/ga/.mozilla 2>/dev/null || true

# Start Firefox
echo "Starting Firefox..."
if snap list firefox &>/dev/null 2>&1; then
    FF_PROFILE="$FF_SNAP/nosh.profile"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /snap/bin/firefox --new-instance -profile '$FF_PROFILE' 'http://localhost/login' > /tmp/firefox_task.log 2>&1 &"
else
    FF_PROFILE="$FF_NATIVE/default-release"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox -profile '$FF_PROFILE' 'http://localhost/login' > /tmp/firefox_task.log 2>&1 &"
fi

# Wait for window
sleep 5
for i in $(seq 1 30); do
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla\|nosh" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Firefox window found: $WID"
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
        # Maximize
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="