#!/bin/bash
set -e
echo "=== Setting up task: add_locker_inventory ==="

# 1. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Database and Web Server are running
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Wait for MariaDB to be responsive
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# 3. Clean Slate: Remove specific lockers if they already exist
# This ensures the agent must actually create them
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "DELETE FROM lockers WHERE locker_number IN ('N-100', 'N-101', 'N-102');" 2>/dev/null || true

# 4. Record Initial State (Max Locker ID)
# Used to verify new records are created *after* task start
MAX_ID=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e "SELECT MAX(locker_id) FROM lockers" 2>/dev/null || echo "0")
if [ "$MAX_ID" == "NULL" ] || [ -z "$MAX_ID" ]; then MAX_ID=0; fi
echo "$MAX_ID" > /tmp/initial_max_locker_id.txt
echo "Initial Max Locker ID: $MAX_ID"

# 5. Ensure Admin User has permissions for Lockers module
# Sometimes default profiles restrict access to specific modules
mysql -u opensis_user -p'opensis_password_123' opensis -e "
INSERT INTO profile_exceptions (profile_id, modname, can_use, can_edit) 
VALUES (1, 'schoolsetup/Lockers.php', 'Y', 'Y') 
ON DUPLICATE KEY UPDATE can_use='Y', can_edit='Y';
" 2>/dev/null || true

# 6. Launch Browser
# Kill any existing instances
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true
sleep 1

# Determine browser command
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser"
fi

# Launch
echo "Starting Chrome..."
nohup sudo -u ga $CHROME_CMD \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --no-sandbox \
    --disable-gpu \
    --start-maximized \
    --password-store=basic \
    "http://localhost/opensis/" > /home/ga/chrome_task.log 2>&1 &

# 7. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        echo "Browser window detected"
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || DISPLAY=:1 wmctrl -a "Chromium" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="