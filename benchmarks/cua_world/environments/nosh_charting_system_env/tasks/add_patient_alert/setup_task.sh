#!/bin/bash
set -e
echo "=== Setting up add_patient_alert task ==="

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Database is ready
echo "Waiting for database connection..."
until docker exec nosh-db mysqladmin ping -h localhost -uroot -prootpassword --silent; do
    echo "  Waiting for DB..."
    sleep 2
done

# 3. Insert/Ensure Patient Data Exists
# using a specific high PID to avoid collision with Synthea data
echo "Ensuring patient Robert Thompson exists..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT IGNORE INTO demographics (pid, firstname, lastname, DOB, sex, address, city, state, zip, phone_home, email) 
VALUES (9901, 'Robert', 'Thompson', '1962-07-14', 'Male', '452 Pine St', 'Springfield', 'MA', '01105', '413-555-0199', 'bob.thompson@example.com');
INSERT IGNORE INTO demographics_relate (pid, id, practice_id) VALUES (9901, 2, 1);
"

# 4. Clear any existing alerts for this patient to ensure clean state
echo "Clearing existing alerts for patient..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e "DELETE FROM alerts WHERE pid = 9901;"

# Record initial alert count (should be 0)
INITIAL_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT COUNT(*) FROM alerts WHERE pid = 9901;")
echo "$INITIAL_COUNT" > /tmp/initial_alert_count.txt
echo "Initial alert count: $INITIAL_COUNT"

# 5. Prepare Browser (Firefox)
echo "Preparing Firefox..."
# Kill existing instances
pkill -9 -f firefox || true
sleep 2

# Clean profiles/locks
rm -f /home/ga/.mozilla/firefox/*.default-release/lock
rm -f /home/ga/.mozilla/firefox/*.default-release/.parentlock

# Start Firefox
if command -v firefox &> /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/login' &"
elif snap list firefox &> /dev/null; then
    su - ga -c "DISPLAY=:1 /snap/bin/firefox 'http://localhost/login' &"
fi

# Wait for window
echo "Waiting for Firefox window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|nosh"; then
        echo "Firefox detected."
        break
    fi
    sleep 1
done

# Maximize and focus
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|nosh" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# 6. Capture Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png || true

echo "=== Setup complete ==="