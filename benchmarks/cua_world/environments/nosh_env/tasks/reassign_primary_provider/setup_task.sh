#!/bin/bash
set -e
echo "=== Setting up task: Reassign Primary Provider ==="

# 1. Record start time
date +%s > /tmp/task_start_time.txt

# 2. Database Setup via Docker
# We need patient 'Timothy Fey' to exist and be assigned to 'Dr. Sarah Admin' (ID 1).
# Target is 'Dr. James Carter' (ID 2).

echo "Configuring database state..."

# Ensure Dr. James Carter (ID 2) exists (should be from env setup, but safe to ignore if exists)
PROV_HASH='$2y$10$6tBChBBTMVa1E3iqLI9.u.vT2Uyunn6F.jrEqN.9YLq/f.TMzI3.'
docker exec nosh-db mysql -uroot -prootpassword nosh -e "INSERT IGNORE INTO users (id, username, displayname, firstname, lastname, password, group_id, active, practice_id) VALUES (2, 'demo_provider', 'Dr. James Carter', 'James', 'Carter', '$PROV_HASH', 2, 1, 1);"

# Find or Create Patient Timothy Fey
# Check if exists
PID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT pid FROM demographics WHERE firstname='Timothy' AND lastname='Fey' LIMIT 1;")

if [ -z "$PID" ]; then
    echo "Creating patient Timothy Fey..."
    docker exec nosh-db mysql -uroot -prootpassword nosh -e "INSERT INTO demographics (firstname, lastname, DOB, sex, active) VALUES ('Timothy', 'Fey', '1980-01-01', 'Male', 1);"
    PID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT pid FROM demographics WHERE firstname='Timothy' AND lastname='Fey' LIMIT 1;")
fi

echo "Patient PID: $PID"
echo "$PID" > /tmp/target_pid.txt

# 3. Set Initial Assignment to Dr. Sarah Admin (ID 1)
# NOSH uses 'demographics_relate' table to link patients (pid) to providers (id)
# Clear existing relationships for this patient
docker exec nosh-db mysql -uroot -prootpassword nosh -e "DELETE FROM demographics_relate WHERE pid = $PID;"

# Insert relationship to Admin (ID 1)
docker exec nosh-db mysql -uroot -prootpassword nosh -e "INSERT INTO demographics_relate (pid, id, practice_id) VALUES ($PID, 1, 1);"

echo "Reset assignment for Timothy Fey (PID $PID) to Dr. Sarah Admin (ID 1)"

# 4. Prepare Browser
# Kill existing Firefox to ensure clean state
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Clean locks
find /home/ga/.mozilla/firefox -name "*.lock" -delete 2>/dev/null || true
find /home/ga/.mozilla/firefox -name ".parentlock" -delete 2>/dev/null || true

# Start Firefox
echo "Starting Firefox..."
if snap list firefox &>/dev/null 2>&1; then
    # Snap specific launch
    su - ga -c "DISPLAY=:1 /snap/bin/firefox 'http://localhost/login' > /tmp/firefox.log 2>&1 &"
else
    # Native launch
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/login' > /tmp/firefox.log 2>&1 &"
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Capture initial state
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="