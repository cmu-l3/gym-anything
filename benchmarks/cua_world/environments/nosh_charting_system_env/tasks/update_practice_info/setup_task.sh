#!/bin/bash
# Setup task: update_practice_info
# Purpose: Ensure practice info is in "Springfield" state and browser is ready at login

echo "=== Setting up update_practice_info task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Reset Practice Info to Initial "Springfield" State
# This ensures the task is repeatable and starts from a known bad state
echo "Resetting practice database records..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e "UPDATE practiceinfo SET \
    street_address1='100 Main St', \
    city='Springfield', \
    state='MA', \
    zip='01101', \
    phone='413-555-1234', \
    fax='413-555-5678', \
    email='admin@hillsidefm.local', \
    practice_name='Hillside Family Medicine' \
    WHERE practice_id=1;" 2>/dev/null || true

# 3. Snapshot initial state for verification
echo "Recording initial database state..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e "SELECT * FROM practiceinfo WHERE practice_id=1\G" > /tmp/initial_practice_info.txt

# 4. Prepare Browser (Standard Firefox Setup)
echo "Preparing Firefox..."
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Clean locks
find /home/ga/.mozilla/firefox -name "*.lock" -delete 2>/dev/null || true
find /home/ga/snap/firefox/common/.mozilla/firefox -name "*.lock" -delete 2>/dev/null || true

# Launch Firefox
OPEN_URL="http://localhost/login"
if snap list firefox &>/dev/null 2>&1; then
    # Snap firefox
    FF_PROFILE="/home/ga/snap/firefox/common/.mozilla/firefox/nosh.profile"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /snap/bin/firefox --new-instance -profile '$FF_PROFILE' '$OPEN_URL' > /dev/null 2>&1 &"
else
    # Native firefox
    FF_PROFILE="/home/ga/.mozilla/firefox/default-release"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox -profile '$FF_PROFILE' '$OPEN_URL' > /dev/null 2>&1 &"
fi

# 5. Wait for Window and Maximize
echo "Waiting for browser window..."
for i in {1..30}; do
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla\|nosh" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Window found: $WID"
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        sleep 0.5
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 6. Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="