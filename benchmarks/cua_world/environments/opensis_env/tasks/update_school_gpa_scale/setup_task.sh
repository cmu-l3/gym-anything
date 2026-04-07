#!/bin/bash
set -e
echo "=== Setting up update_school_gpa_scale task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure Database Service is running
if ! systemctl is-active --quiet mariadb; then
    echo "Starting MariaDB..."
    systemctl start mariadb
    sleep 3
fi

# 3. Ensure Apache Service is running
if ! systemctl is-active --quiet apache2; then
    echo "Starting Apache..."
    systemctl start apache2
    sleep 2
fi

# Wait for database to be ready
echo "Waiting for database..."
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# 4. Set Initial State (Reset GP Scale to 4.00)
# This guarantees that if the final value is 5.00, the agent must have changed it.
echo "Resetting Reporting GP Scale to 4.00..."
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "UPDATE schools SET reporting_gp_scale = 4.00 WHERE title = 'Demo School';" 2>/dev/null

# Record initial state for debugging/verification
INITIAL_VAL=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e \
    "SELECT reporting_gp_scale FROM schools WHERE title = 'Demo School';" 2>/dev/null)
echo "$INITIAL_VAL" > /tmp/initial_gpa_scale.txt
echo "Initial GP Scale set to: $INITIAL_VAL"

# 5. Prepare Browser (Open Login Page)
# Kill existing instances to ensure clean state
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true

echo "Starting Chrome..."
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser"
fi

# Launch Chrome as user 'ga'
su - ga -c "DISPLAY=:1 $CHROME_CMD --no-sandbox --start-maximized --disable-gpu http://localhost/opensis/ &"
sleep 5

# 6. Ensure Window is Maximized and Focused
# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Focus
DISPLAY=:1 wmctrl -a "Opensis" 2>/dev/null || true

# 7. Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="