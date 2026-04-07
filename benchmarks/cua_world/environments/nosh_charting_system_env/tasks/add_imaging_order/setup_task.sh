#!/bin/bash
set -e
echo "=== Setting up add_imaging_order task ==="

# Source shared utilities if available, otherwise define basics
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. ESTABLISH BASELINE TIMESTAMP
date +%s > /tmp/task_start_time.txt

# 2. ENSURE PATIENT EXISTS
# We explicitly insert Robert Murphy to ensure the agent has the specific target.
# Using INSERT IGNORE to avoid duplicates if run multiple times.
echo "Ensuring patient Robert Murphy exists..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
"INSERT IGNORE INTO demographics (pid, lastname, firstname, DOB, sex, active) VALUES (9901, 'Murphy', 'Robert', '1972-08-15', 'm', 1);" 2>/dev/null

# Link patient to practice (required for them to appear in searches)
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
"INSERT IGNORE INTO demographics_relate (pid, id, practice_id) VALUES (9901, 2, 1);" 2>/dev/null

# 3. RECORD INITIAL STATE (Anti-Gaming)
# Count existing radiology orders for this patient
INITIAL_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
"SELECT COUNT(*) FROM orders WHERE pid=9901 AND (orders_type='rad' OR orders_type='image' OR orders_type LIKE '%rad%');" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_order_count.txt
echo "Initial order count: $INITIAL_COUNT"

# 4. PREPARE BROWSER ENVIRONMENT
# Clean up any existing Firefox instances
pkill -9 -f firefox 2>/dev/null || true
rm -rf /home/ga/.mozilla/firefox/*.default-release/sessionstore.jsonlz4 2>/dev/null || true

# 5. LAUNCH FIREFOX TO LOGIN PAGE
echo "Launching Firefox..."
if snap list firefox &>/dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 /snap/bin/firefox --new-instance http://localhost/login &"
else
    su - ga -c "DISPLAY=:1 firefox http://localhost/login &"
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Mozilla Firefox"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 6. AUTOMATE LOGIN (to satisfy "Starting State: User is logged in")
# We use xdotool to type credentials. This ensures the agent starts at the dashboard.
echo "Logging in..."
# Focus window
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true
sleep 1

# Type username
DISPLAY=:1 xdotool type "demo_provider"
DISPLAY=:1 xdotool key Tab
sleep 0.5
# Type password
DISPLAY=:1 xdotool type "Provider1234!"
DISPLAY=:1 xdotool key Return

# Wait for login to complete (dashboard load)
sleep 5

# Dismiss any potential "Save Password" dialogs or popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 7. CAPTURE INITIAL EVIDENCE
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="