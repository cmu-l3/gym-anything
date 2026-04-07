#!/bin/bash
echo "=== Setting up add_vaccine_inventory task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up: Remove the target lot if it already exists to ensure fresh entry
#    Trying common table names for vaccine inventory in NOSH/OpenEMR variants
echo "Cleaning up previous test data..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "DELETE FROM vaccine_inventory WHERE lot_number='FL-2026-QA';" 2>/dev/null || true
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "DELETE FROM inventory WHERE lot='FL-2026-QA';" 2>/dev/null || true

# 3. Ensure Firefox is fresh and ready
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Clean Firefox locks
rm -f /home/ga/.mozilla/firefox/*.default-release/lock
rm -f /home/ga/.mozilla/firefox/*.default-release/.parentlock
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*.default/lock

# 4. Start Firefox and automate login (since task description implies logged-in state or easy login)
#    We will load the login page. The agent is responsible for logging in, 
#    but we can pre-fill or just land on the page as per "Starting State" description.
#    The description says "Firefox is open and logged into NOSH... or log in as admin".
#    To be safe and consistent with other tasks, we'll start at login page.
echo "Starting Firefox..."
NOSH_URL="http://localhost/login"
su - ga -c "DISPLAY=:1 firefox '$NOSH_URL' > /tmp/firefox.log 2>&1 &"

# 5. Wait for Firefox window and maximize
echo "Waiting for Firefox..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        echo "Firefox detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# 6. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="