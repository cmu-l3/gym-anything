#!/bin/bash
# Setup script for Add Pharmacy Address Book task
set -e

echo "=== Setting up add_pharmacy_addressbook task ==="

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Clean state: Remove any existing entry for "Springfield Family Pharmacy" to prevent duplicates or false positives
echo "Cleaning up any existing entries..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "DELETE FROM addressbook WHERE displayname LIKE '%Springfield Family Pharmacy%' OR facility LIKE '%Springfield Family Pharmacy%';" 2>/dev/null || true

# 3. Record initial count of addressbook entries
INITIAL_COUNT=$(docker exec nosh-db mysql -N -uroot -prootpassword nosh -e "SELECT COUNT(*) FROM addressbook;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_addressbook_count.txt
echo "Initial address book count: $INITIAL_COUNT"

# 4. Ensure Firefox is running and at login page
echo "Launching Firefox..."
pkill -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox pointing to NOSH login
if snap list firefox &>/dev/null 2>&1; then
    FF_PROFILE="/home/ga/snap/firefox/common/.mozilla/firefox/nosh.profile"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /snap/bin/firefox --new-instance -profile '$FF_PROFILE' 'http://localhost/login' > /tmp/firefox_task.log 2>&1 &"
else
    FF_PROFILE="/home/ga/.mozilla/firefox/default-release"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox -profile '$FF_PROFILE' 'http://localhost/login' > /tmp/firefox_task.log 2>&1 &"
fi

# 5. Wait for window and maximize
echo "Waiting for Firefox window..."
for i in {1..30}; do
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla\|nosh" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Window found: $WID"
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        sleep 1
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 6. Capture initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="