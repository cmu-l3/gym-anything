#!/bin/bash
# Setup task: update_patient_demographics
# Goal: Insert patient Eleanor Whitfield with OLD data so the agent can update it.

set -e
echo "=== Setting up update_patient_demographics task ==="

# 1. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Database Setup
# We need to insert the patient with the "OLD" values.
# PID 9000 is used to avoid conflicts with Synthea data (usually 1-100) or auto-increments.

echo "Preparing database..."

# Clean up any previous runs
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM demographics WHERE firstname='Eleanor' AND lastname='Whitfield';" 2>/dev/null || true

# Insert Patient Record (OLD DATA)
# Note: active=1 is crucial for them to show up in search
docker exec nosh-db mysql -uroot -prootpassword nosh -e "
INSERT INTO demographics (
    pid, firstname, lastname, DOB, sex, 
    address, city, state, zip, 
    phone_home, email, active
) VALUES (
    9000, 'Eleanor', 'Whitfield', '1958-04-12', 'Female',
    '45 Oak Lane', 'Hartford', 'CT', '06103',
    '860-555-0147', 'ewhitfield@email.com', 1
);"

# Link patient to practice (demographics_relate)
# Assuming practice_id=1 (default) and provider_id=1 (admin)
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "INSERT INTO demographics_relate (pid, practice_id) VALUES (9000, 1);" 2>/dev/null || true

# Record initial state to a file for verification (evidence that values were different)
echo "Recording initial state..."
docker exec nosh-db mysql -uroot -prootpassword nosh -B -e \
  "SELECT address, city, zip, phone_home, email FROM demographics WHERE pid=9000" \
  > /tmp/initial_db_state.txt

# 3. Application Setup (Firefox)
echo "Configuring Firefox..."
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Clean locks
find /home/ga/.mozilla -name "*.lock" -delete 2>/dev/null || true
find /home/ga/snap -name "*.lock" -delete 2>/dev/null || true

# Start Firefox at login page
if snap list firefox &>/dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 setsid /snap/bin/firefox --new-instance 'http://localhost/login' > /dev/null 2>&1 &"
else
    su - ga -c "DISPLAY=:1 setsid firefox 'http://localhost/login' > /dev/null 2>&1 &"
fi

# Wait for window
echo "Waiting for Firefox..."
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

# 4. Evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="