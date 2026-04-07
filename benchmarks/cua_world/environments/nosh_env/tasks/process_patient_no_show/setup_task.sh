#!/bin/bash
echo "=== Setting up process_patient_no_show task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Calculate yesterday's date
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
echo "Target Date: $YESTERDAY" > /tmp/target_date.txt

# 1. Create patient 'Michael Absent' (PID 10001) if not exists
echo "Creating patient Michael Absent..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "INSERT IGNORE INTO demographics (pid, firstname, lastname, dob, sex, active, practice_id) VALUES (10001, 'Michael', 'Absent', '1980-01-01', 'Male', 1, 1);" 2>/dev/null

# 2. Insert appointment for Yesterday at 14:00
# Provider ID 2 is likely 'demo_provider' based on setup_nosh.sh
# We verify the schedule table columns or just use standard NOSH v2 structure
echo "Creating appointment for yesterday ($YESTERDAY)..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "INSERT INTO schedule (pid, provider_id, date, start_time, end_time, status, reason, visit_type_id, practice_id) \
   VALUES (10001, 2, '$YESTERDAY', '14:00:00', '14:15:00', 'active', 'Follow-up', 1, 1);" 2>/dev/null

# Get the ID of the inserted appointment for verification
APPT_ID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT id FROM schedule WHERE pid=10001 AND date='$YESTERDAY' AND start_time='14:00:00' ORDER BY id DESC LIMIT 1;")
echo "$APPT_ID" > /tmp/target_appt_id.txt
echo "Created Appointment ID: $APPT_ID"

# 3. Ensure Firefox is running
pkill -9 -f firefox 2>/dev/null || true
sleep 2

FF_SNAP="/home/ga/snap/firefox/common/.mozilla/firefox"
FF_NATIVE="/home/ga/.mozilla/firefox"

# Cleanup locks
for profile_dir in "$FF_SNAP" "$FF_NATIVE"; do
    if [ -d "$profile_dir" ]; then
        find "$profile_dir" -name ".parentlock" -delete 2>/dev/null || true
        find "$profile_dir" -name "lock" -delete 2>/dev/null || true
    fi
done

# Launch Firefox
if snap list firefox &>/dev/null 2>&1; then
    FF_PROFILE="$FF_SNAP/nosh.profile"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /snap/bin/firefox --new-instance -profile '$FF_PROFILE' 'http://localhost/login' > /tmp/firefox_task.log 2>&1 &"
else
    FF_PROFILE="$FF_NATIVE/default-release"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox -profile '$FF_PROFILE' 'http://localhost/login' > /tmp/firefox_task.log 2>&1 &"
fi

sleep 8

# Maximize Window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|nosh" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="