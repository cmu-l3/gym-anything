#!/bin/bash
# Setup script for export_patient_ccda task

echo "=== Setting up Export Patient CCDA Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up any previous run artifacts
TARGET_FILE="/home/ga/Documents/maria_rodriguez_ccda.xml"
rm -f "$TARGET_FILE"
# Also clean up Downloads to prevent confusion with old files
rm -f /home/ga/Downloads/*.xml 2>/dev/null || true

# 3. Ensure Firefox is running and at the login page
# Clean up existing firefox instances
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Remove lock files
find /home/ga/.mozilla/firefox -name ".parentlock" -delete 2>/dev/null || true
find /home/ga/.mozilla/firefox -name "lock" -delete 2>/dev/null || true

# Launch Firefox
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/login' > /tmp/firefox.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# 4. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="