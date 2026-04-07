#!/bin/bash
set -e
echo "=== Setting up Reschedule Appointment Task ==="

# 1. Define Dates (Dynamic)
# OLD: Tomorrow at 09:00
# NEW: Tomorrow + 2 days (Total 3 days from now) at 10:30
TODAY=$(date +%Y-%m-%d)
OLD_DATE=$(date -d "+1 day" +%Y-%m-%d)
NEW_DATE=$(date -d "+3 days" +%Y-%m-%d)
OLD_TIME="09:00:00"
NEW_TIME="10:30:00"

OLD_DATETIME="${OLD_DATE} ${OLD_TIME}"
NEW_DATETIME="${NEW_DATE} ${NEW_TIME}"

# Save target info for the export script to use later
echo "$OLD_DATETIME" > /tmp/task_old_datetime.txt
echo "$NEW_DATETIME" > /tmp/task_new_datetime.txt

# 2. Create Request File on Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/reschedule_request.txt <<EOF
RESCHEDULE REQUEST
------------------
Patient: Michael Chang
DOB: 03/12/1975

Current Appointment: ${OLD_DATE} at 9:00 AM
Reason: Routine Checkup

ACTION REQUIRED:
Please reschedule this appointment to:
Date: ${NEW_DATE}
Time: 10:30 AM

Reason for change: Work conflict
EOF

# Set permissions
chown ga:ga /home/ga/Desktop/reschedule_request.txt

# 3. Clean up previous run artifacts (if any)
docker exec nosh-db mysql -uroot -prootpassword nosh -e "DELETE FROM schedule WHERE pid = 999;" 2>/dev/null || true
docker exec nosh-db mysql -uroot -prootpassword nosh -e "DELETE FROM demographics WHERE pid = 999;" 2>/dev/null || true

# 4. Insert Patient (Michael Chang, PID 999)
echo "Inserting patient Michael Chang..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "INSERT IGNORE INTO demographics (pid, firstname, lastname, DOB, sex, active) VALUES (999, 'Michael', 'Chang', '1975-03-12', 'Male', 1);"

# 5. Insert Initial Appointment (Tomorrow 9am)
# Using 'Office Visit' which is standard in the env
echo "Inserting initial appointment at $OLD_DATETIME..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "INSERT INTO schedule (pid, provider_id, start, end, visit_type, reason, status, active) VALUES (999, 2, '${OLD_DATETIME}', DATE_ADD('${OLD_DATETIME}', INTERVAL 30 MINUTE), 'Office Visit', 'Routine Checkup', 'booked', 1);"

# 6. Record Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 7. Launch Firefox
echo "Starting Firefox..."
pkill -f firefox || true
sleep 1

# Launch pointing to login
su - ga -c "DISPLAY=:1 firefox 'http://localhost/login' > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Patient: Michael Chang (PID 999)"
echo "Old Appt: $OLD_DATETIME"
echo "Target Appt: $NEW_DATETIME"