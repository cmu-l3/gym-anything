#!/bin/bash
set -e
echo "=== Setting up configure_school_periods task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Database Services are running
echo "Checking services..."
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Wait for MariaDB
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "MariaDB is ready."
        break
    fi
    sleep 1
done

# 3. Clean State: Remove any existing periods for School ID 1
# This ensures the agent must create them, not just edit existing ones.
echo "Clearing existing periods..."
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "DELETE FROM school_periods WHERE school_id = 1;" 2>/dev/null || true

# Record initial count (should be 0)
INITIAL_COUNT=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e \
    "SELECT COUNT(*) FROM school_periods WHERE school_id = 1" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_period_count.txt
echo "Initial period count: $INITIAL_COUNT"

# 4. Start Chrome and prepare window
echo "Starting Chrome..."
pkill -f chrome 2>/dev/null || true

# Launch Chrome as ga user
su - ga -c 'DISPLAY=:1 google-chrome-stable \
    --no-sandbox \
    --disable-gpu \
    --disable-infobars \
    --no-first-run \
    --password-store=basic \
    "http://localhost/opensis/" > /dev/null 2>&1 &'

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "chrome\|chromium"; then
        echo "Chrome window detected."
        break
    fi
    sleep 1
done

# Maximize and Focus
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="