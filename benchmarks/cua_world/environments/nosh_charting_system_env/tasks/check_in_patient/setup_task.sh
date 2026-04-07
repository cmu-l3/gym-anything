#!/bin/bash
echo "=== Setting up Check In Patient task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure NOSH is running (wait loop handled in env setup, but good to double check)
# We assume the docker container nosh-db and nosh-app are up.

# 1. PREPARE DATA: Ensure Patient Arthur Dent exists
echo "Creating patient Arthur Dent..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "INSERT IGNORE INTO demographics (pid, firstname, lastname, DOB, sex, active) VALUES (99999, 'Arthur', 'Dent', '1970-01-01', 'Male', 1);" 2>/dev/null

# 2. PREPARE DATA: Ensure Appointment exists for TODAY at 10:00 AM
# We delete any existing appt for this patient today to ensure clean state
echo "Setting up appointment..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "DELETE FROM schedule WHERE pid=99999 AND DATE(start) = CURDATE();" 2>/dev/null

# Insert 'Pending' appointment. 
# Note: Provider ID 2 is usually the demo provider 'Dr. James Carter'
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "INSERT INTO schedule (pid, provider_id, start, end, status, reason, visit_type, active) VALUES (99999, 2, CONCAT(CURDATE(), ' 10:00:00'), CONCAT(CURDATE(), ' 10:15:00'), 'Pending', 'Regular Follow-up', 'Office Visit', 1);" 2>/dev/null

# Record initial state of the appointment ID for later verification
APPT_ID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT id FROM schedule WHERE pid=99999 AND DATE(start) = CURDATE();" 2>/dev/null)
echo "$APPT_ID" > /tmp/target_appt_id.txt
echo "Created Appointment ID: $APPT_ID"

# 3. GUI SETUP: Launch Firefox to Login Page
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    # Clean profile handling
    pkill -9 -f firefox 2>/dev/null || true
    rm -f /home/ga/.mozilla/firefox/*.default-release/lock 2>/dev/null || true
    rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*.default/lock 2>/dev/null || true
    
    su - ga -c "DISPLAY=:1 firefox http://localhost/login &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 4. INITIAL SCREENSHOT
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="