#!/bin/bash
set -e
echo "=== Setting up add_teacher_staff task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Database and Web Server are running
echo "Checking services..."
service mariadb start 2>/dev/null || systemctl start mariadb || true
service apache2 start 2>/dev/null || systemctl start apache2 || true

# Wait for MySQL to be ready
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "Database is ready."
        break
    fi
    sleep 1
done

# 3. Clean State: Remove the target user if they already exist (Idempotency)
echo "Cleaning up any previous records for 'mchen'..."
mysql -u opensis_user -p'opensis_password_123' opensis -e "
DELETE FROM staff_school_relationship WHERE staff_id IN (SELECT staff_id FROM staff WHERE first_name='Margaret' AND last_name='Chen');
DELETE FROM staff_school_info WHERE staff_id IN (SELECT staff_id FROM staff WHERE first_name='Margaret' AND last_name='Chen');
DELETE FROM login_authentication WHERE username='mchen';
DELETE FROM staff WHERE first_name='Margaret' AND last_name='Chen';
" 2>/dev/null || true

# 4. Record Initial State
INITIAL_COUNT=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e "SELECT COUNT(*) FROM staff" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_staff_count.txt
echo "Initial staff count: $INITIAL_COUNT"

# 5. Launch Application (Chrome)
# Kill existing instances
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true

echo "Starting Chrome..."
# Launch as user 'ga'
if command -v google-chrome-stable &> /dev/null; then
    BROWSER="google-chrome-stable"
else
    BROWSER="chromium-browser"
fi

su - ga -c "DISPLAY=:1 $BROWSER \
    --no-first-run \
    --no-default-browser-check \
    --password-store=basic \
    --start-maximized \
    http://localhost/opensis/ &"

# 6. Wait for Window and Focus
echo "Waiting for browser window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i -E "chrome|chromium|opensis"; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenSIS" 2>/dev/null || true

# 7. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="