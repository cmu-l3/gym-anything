#!/bin/bash
set -e
echo "=== Setting up create_user_profile task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
service mariadb start || true
service apache2 start || true

# Wait for database
for i in {1..30}; do
    if mysql -u opensis_user -popensis_password_123 -e "SELECT 1" opensis >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Record initial max profile ID to distinguish new profiles later
INITIAL_MAX_ID=$(mysql -u opensis_user -popensis_password_123 opensis -N -e "SELECT COALESCE(MAX(id), 0) FROM user_profiles" 2>/dev/null || echo "0")
echo "$INITIAL_MAX_ID" > /tmp/initial_max_profile_id.txt

# Start Chrome
if ! pgrep -f "chrome" > /dev/null; then
    echo "Starting Chrome..."
    # Use generic chrome launch command found in other tasks
    su - ga -c "DISPLAY=:1 google-chrome-stable --no-sandbox --start-maximized http://localhost/opensis/ &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "chrome"; then
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="