#!/bin/bash
# Setup script for create_letter_template task

echo "=== Setting up create_letter_template task ==="

# 1. Record start time for anti-gaming (timestamp check)
date +%s > /tmp/task_start_time.txt

# 2. Cleanup: Remove any existing template with this name to ensure a fresh start
# We try multiple likely tables where templates might be stored in NOSH to ensure clean state
echo "Cleaning up existing templates..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "DELETE FROM form_layout WHERE form_name = 'New Patient Welcome';" 2>/dev/null || true
docker exec nosh-db mysql -uroot -prootpassword nosh -e \
    "DELETE FROM documents_templates WHERE title = 'New Patient Welcome';" 2>/dev/null || true

# 3. Ensure Firefox is fresh and ready
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Remove lock files
find /home/ga/.mozilla -name "*.lock" -delete 2>/dev/null || true
find /home/ga/snap/firefox -name "*.lock" -delete 2>/dev/null || true

# 4. Start Firefox at Login Page
echo "Starting Firefox..."
if snap list firefox &>/dev/null 2>&1; then
    FF_CMD="/snap/bin/firefox"
else
    FF_CMD="firefox"
fi

su - ga -c "DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority setsid $FF_CMD --new-instance 'http://localhost/login' > /tmp/firefox.log 2>&1 &"

# 5. Wait for window and maximize
echo "Waiting for Firefox..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|nosh"; then
        echo "Firefox detected."
        WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|nosh" | head -1 | awk '{print $1}')
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null
        break
    fi
    sleep 1
done

# 6. Capture Initial State Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="