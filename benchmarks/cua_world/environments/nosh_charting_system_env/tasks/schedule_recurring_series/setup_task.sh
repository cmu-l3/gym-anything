#!/bin/bash
# Setup script for schedule_recurring_series task

echo "=== Setting up Schedule Recurring Series Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Patient Eulalia Hammes exists (PID 19 from standard Synthea set usually, but we'll find by name)
# We need to get her PID to clean the schedule
echo "Locating patient..."
PATIENT_ID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT pid FROM demographics WHERE lastname='Hammes' AND firstname='Eulalia' LIMIT 1" 2>/dev/null)

if [ -z "$PATIENT_ID" ]; then
    echo "Patient not found, creating placeholder..."
    # Insert if missing (fallback)
    docker exec nosh-db mysql -uroot -prootpassword nosh -e "INSERT INTO demographics (firstname, lastname, DOB, sex) VALUES ('Eulalia', 'Hammes', '1974-04-14', 'Female');"
    PATIENT_ID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT pid FROM demographics WHERE lastname='Hammes' AND firstname='Eulalia' LIMIT 1" 2>/dev/null)
fi

echo "Patient PID: $PATIENT_ID"
echo "$PATIENT_ID" > /tmp/target_pid.txt

# Clear any existing appointments for this patient in April 2026 to ensure clean state
# NOSH likely uses 'schedule' table. Columns usually: id, pid, start_date, start_time, end_time, reason, type
echo "Clearing conflicting appointments..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e "DELETE FROM schedule WHERE pid='$PATIENT_ID' AND start_date >= '2026-04-01' AND start_date <= '2026-04-30';" 2>/dev/null || true

# Also clear specifically the 9am slots for ANY patient to prevent blocked slots
DATES=("2026-04-06" "2026-04-13" "2026-04-20" "2026-04-27")
for d in "${DATES[@]}"; do
    docker exec nosh-db mysql -uroot -prootpassword nosh -e "DELETE FROM schedule WHERE start_date='$d' AND start_time='09:00:00';" 2>/dev/null || true
done

# Restart/Clean Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Launch Firefox to Login
echo "Launching Firefox..."
FF_PROFILE="/home/ga/.mozilla/firefox/nosh.profile"
mkdir -p "$FF_PROFILE"

su - ga -c "DISPLAY=:1 setsid firefox -profile '$FF_PROFILE' 'http://localhost/login' > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|nosh"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="