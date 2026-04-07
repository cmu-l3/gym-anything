#!/bin/bash
# Setup script for schedule_patient_reminder
# Target: Patient Lucinda Haag (PID 3)
# Goal: Ensure clean state (no existing Mammogram reminder) and open Login

echo "=== Setting up Schedule Patient Reminder Task ==="

# 1. Record Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt
echo "Task started at: $(cat /tmp/task_start_time.txt)"

# 2. Clean up existing 'Mammogram' reminders for this patient to ensure fresh entry
# We use docker exec to run the cleanup SQL inside the database container
echo "Cleaning up existing reminders..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
  "DELETE FROM reminders WHERE pid=3 AND reminder LIKE '%Mammogram%';" 2>/dev/null || true

# 3. Prepare Firefox
# Kill any existing Firefox instances
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Clean up lock files that might prevent Firefox from starting
find /home/ga/.mozilla/firefox -name "*.lock" -delete 2>/dev/null || true
find /home/ga/snap/firefox/common/.mozilla/firefox -name "*.lock" -delete 2>/dev/null || true

# Start Firefox pointing to NOSH Login
echo "Starting Firefox..."
LOGIN_URL="http://localhost/login"

# Check if using Snap or Native Firefox
if snap list firefox &>/dev/null 2>&1; then
    FF_CMD="/snap/bin/firefox"
else
    FF_CMD="firefox"
fi

su - ga -c "DISPLAY=:1 $FF_CMD --new-instance '$LOGIN_URL' > /tmp/firefox_task.log 2>&1 &"

# 4. Wait for Window and Maximize
echo "Waiting for Firefox window..."
for i in {1..30}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "Mozilla Firefox\|NOSH" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        echo "Firefox window found: $WID"
        # Activate and maximize
        DISPLAY=:1 wmctrl -ia "$WID"
        sleep 0.5
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
        break
    fi
    sleep 1
done

# 5. Take Initial Screenshot
sleep 2
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="