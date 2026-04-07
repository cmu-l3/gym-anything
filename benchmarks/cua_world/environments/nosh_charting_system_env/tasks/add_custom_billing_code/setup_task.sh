#!/bin/bash
echo "=== Setting up Add Custom Billing Code Task ==="

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure clean state: Delete the target code if it already exists
# This ensures the agent MUST create it to pass
echo "Cleaning up any existing code 'SPT-PHY'..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "DELETE FROM cpt WHERE code='SPT-PHY';" 2>/dev/null || true

# 3. Setup Firefox
# Kill any existing instances
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Clear locks/profiles to ensure clean start
find /home/ga/.mozilla/firefox -name ".parentlock" -delete 2>/dev/null || true
find /home/ga/.mozilla/firefox -name "lock" -delete 2>/dev/null || true
find /home/ga/snap/firefox/common/.mozilla/firefox -name ".parentlock" -delete 2>/dev/null || true

# Start Firefox pointing to Login page
echo "Starting Firefox..."
NOSH_URL="http://localhost/login"

if snap list firefox &>/dev/null 2>&1; then
    # Snap Firefox
    FF_PROFILE="/home/ga/snap/firefox/common/.mozilla/firefox/nosh.profile"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /snap/bin/firefox --new-instance -profile '$FF_PROFILE' '$NOSH_URL' > /tmp/firefox_task.log 2>&1 &"
else
    # Native Firefox
    FF_PROFILE="/home/ga/.mozilla/firefox/default-release"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox -profile '$FF_PROFILE' '$NOSH_URL' > /tmp/firefox_task.log 2>&1 &"
fi

# 4. Wait for window and maximize
echo "Waiting for Firefox window..."
for i in {1..30}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|nosh" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Window found: $WID"
        # Focus
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        sleep 1
        # Maximize
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 5. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="