#!/bin/bash
# Setup task: cancel_appointment
# Target patient: Charles Nolan (pid=4)
# Pre-schedules an appointment that the agent must cancel
# Start state: NOSH login page
echo "=== Setting up cancel_appointment task ==="

# Remove any previously scheduled appointments for this patient on target date
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM schedule WHERE pid=4 AND start BETWEEN UNIX_TIMESTAMP('2026-07-15 00:00:00') AND UNIX_TIMESTAMP('2026-07-15 23:59:59');" 2>/dev/null || true

# Insert a pre-scheduled appointment for Charles Nolan on July 15, 2026 at 10:00 AM
# Schedule table: schedule_id, pid, provider_id, start, end, visit_type, status, practice_id
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "INSERT INTO schedule (pid, provider_id, user_id, start, end, visit_type, status, title, timestamp) VALUES (4, 2, 2, UNIX_TIMESTAMP('2026-07-15 10:00:00'), UNIX_TIMESTAMP('2026-07-15 10:30:00'), 'Office Visit', 'y', 'Charles Nolan - Office Visit', NOW());" 2>/dev/null || true

# Kill existing Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 3

FF_SNAP="/home/ga/snap/firefox/common/.mozilla/firefox"
FF_NATIVE="/home/ga/.mozilla/firefox"
for profile_dir in "$FF_SNAP" "$FF_NATIVE"; do
    if [ -d "$profile_dir" ]; then
        find "$profile_dir" -name ".parentlock" -delete 2>/dev/null || true
        find "$profile_dir" -name "lock" -delete 2>/dev/null || true
    fi
done

chown -R ga:ga /home/ga/snap 2>/dev/null || true
chown -R ga:ga /home/ga/.mozilla 2>/dev/null || true

if snap list firefox &>/dev/null 2>&1; then
    FF_PROFILE="$FF_SNAP/nosh.profile"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid /snap/bin/firefox --new-instance -profile '$FF_PROFILE' 'http://localhost/login' > /tmp/firefox_task.log 2>&1 &"
else
    FF_PROFILE="$FF_NATIVE/default-release"
    mkdir -p "$FF_PROFILE"
    su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid firefox -profile '$FF_PROFILE' 'http://localhost/login' > /tmp/firefox_task.log 2>&1 &"
fi

sleep 5

for i in $(seq 1 20); do
    WID=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla\|nosh" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== Task setup complete: cancel_appointment ==="
echo "Appointment for Charles Nolan on 2026-07-15 10:00 has been pre-scheduled."
echo "NOSH login page is open. Agent should log in as demo_provider and cancel the appointment."
