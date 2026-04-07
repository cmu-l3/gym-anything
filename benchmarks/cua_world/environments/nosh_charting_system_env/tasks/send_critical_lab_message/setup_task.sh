#!/bin/bash
echo "=== Setting up send_critical_lab_message task ==="

# Source shared utilities if available, otherwise define basics
mkdir -p /tmp

# Record task start time (for anti-gaming timestamp checks)
# Using date +%s for Unix timestamp
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# Ensure NOSH database is ready
echo "Waiting for database connection..."
until docker exec nosh-db mysqladmin ping -h localhost -uroot -prootpassword --silent; do
    echo "Waiting for database..."
    sleep 2
done

# DATA PREPARATION
# 1. ensure patient Maria Rodriguez exists (using SQL to check/verify)
# We assume the Synthea dataset loaded her, but we get her PID to be sure.
PATIENT_ID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT pid FROM demographics WHERE firstname='Maria' AND lastname='Rodriguez' LIMIT 1")

if [ -z "$PATIENT_ID" ]; then
    echo "WARNING: Patient Maria Rodriguez not found. Creating fallback patient..."
    # Insert fallback patient if missing
    docker exec nosh-db mysql -uroot -prootpassword nosh -e "INSERT INTO demographics (firstname, lastname, DOB, sex, active) VALUES ('Maria', 'Rodriguez', '1978-06-14', 'Female', 1);"
fi

# 2. Clean up previous attempts to ensure verification is fresh
# Delete messages to demo_provider regarding Maria Rodriguez with "URGENT" in subject created in last 24h
echo "Cleaning up stale messages..."
docker exec nosh-db mysql -uroot -prootpassword nosh -e "DELETE FROM messaging WHERE subject LIKE '%URGENT%' AND body LIKE '%6.2%';" 2>/dev/null || true

# APP SETUP
# Kill existing Firefox instances to ensure clean slate
pkill -9 -f firefox 2>/dev/null || true
sleep 2

# Clear firefox locks
rm -f /home/ga/.mozilla/firefox/*.default-release/lock
rm -f /home/ga/.mozilla/firefox/*.default-release/.parentlock

# Start Firefox on Login Page
echo "Starting Firefox..."
NOSH_URL="http://localhost/login"
su - ga -c "DISPLAY=:1 firefox '$NOSH_URL' > /dev/null 2>&1 &"

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

echo "=== Task setup complete ==="