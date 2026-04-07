#!/bin/bash
echo "=== Setting up create_patient_form_template task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# ==============================================================================
# 1. Clean Slate: Remove any existing "COVID-19 Screening" forms
# ==============================================================================
# Since we don't know the exact internal table for custom templates without inspection,
# we'll try a broad delete if possible, or just log the initial state.
# NOSH custom forms often reside in tables like 'form_layout' or are serialized.
# We will rely on the "grep dump" method for verification, so strictly speaking
# we just need to ensure the string isn't there to start with, or record that it was.

echo "Checking for pre-existing form data..."
docker exec nosh-db mysqldump -uroot -prootpassword nosh > /tmp/nosh_initial_dump.sql 2>/dev/null

if grep -qi "COVID-19 Screening" /tmp/nosh_initial_dump.sql; then
    echo "WARNING: Form already exists in DB. Attempting to clean..."
    # Attempt to delete from common candidate tables (heuristic)
    docker exec nosh-db mysql -uroot -prootpassword nosh -e "DELETE FROM forms_layout WHERE form_name LIKE '%COVID-19 Screening%';" 2>/dev/null || true
    docker exec nosh-db mysql -uroot -prootpassword nosh -e "DELETE FROM encounter_forms WHERE title LIKE '%COVID-19 Screening%';" 2>/dev/null || true
fi

# ==============================================================================
# 2. Browser Setup
# ==============================================================================
# Kill existing Firefox
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Clean profiles to prevent lock issues
rm -rf /home/ga/.mozilla/firefox/*.default-release/lock
rm -rf /home/ga/.mozilla/firefox/*.default-release/.parentlock

# Start Firefox at Login Page
echo "Starting Firefox..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/login' > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        echo "Firefox window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="