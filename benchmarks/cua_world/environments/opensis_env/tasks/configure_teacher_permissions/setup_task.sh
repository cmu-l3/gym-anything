#!/bin/bash
set -e
echo "=== Setting up Configure Teacher Permissions Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure services are running
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true
sleep 3

# Database configuration
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME"

# 1. Ensure Teacher profile exists (ID=2)
echo "Ensuring Teacher profile exists..."
$MYSQL_CMD -e "INSERT INTO user_profiles (id, profile, title) VALUES (2, 'teacher', 'Teacher') ON DUPLICATE KEY UPDATE profile='teacher', title='Teacher';" 2>/dev/null || true

# 2. CRITICAL: Wipe existing permissions for Teacher profile
# This ensures a clean state and forces the agent to actually perform the configuration
echo "Wiping existing permissions for Teacher profile..."
$MYSQL_CMD -e "DELETE FROM profile_exceptions WHERE profile_id = 2;" 2>/dev/null || true

# 3. Ensure Admin profile (ID=1) has access to Users/User.php so they can perform the task
echo "Ensuring Admin permissions..."
$MYSQL_CMD -e "INSERT INTO profile_exceptions (profile_id, modname, can_use, can_edit) VALUES (1, 'users/User.php', 'Y', 'Y') ON DUPLICATE KEY UPDATE can_use='Y', can_edit='Y';" 2>/dev/null || true
$MYSQL_CMD -e "INSERT INTO profile_exceptions (profile_id, modname, can_use, can_edit) VALUES (1, 'users/UserFields.php', 'Y', 'Y') ON DUPLICATE KEY UPDATE can_use='Y', can_edit='Y';" 2>/dev/null || true

# 4. Record initial state (should be 0)
INITIAL_COUNT=$($MYSQL_CMD -N -e "SELECT COUNT(*) FROM profile_exceptions WHERE profile_id = 2;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_perms_count.txt
echo "Initial teacher permissions count: $INITIAL_COUNT"

# 5. Launch Chrome logged into OpenSIS
# Kill existing Chrome
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true
sleep 1

# Start Chrome
echo "Starting Chrome..."
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser"
fi

nohup sudo -u ga $CHROME_CMD \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --window-size=1920,1080 \
    --disable-infobars \
    --password-store=basic \
    "http://localhost/opensis/" > /home/ga/chrome_opensis.log 2>&1 &

sleep 5

# Wait for window
for i in {1..30}; do
    if wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        echo "Browser window detected"
        break
    fi
    sleep 1
done

# Focus and maximize
wmctrl -a "Chrome" 2>/dev/null || wmctrl -a "Chromium" 2>/dev/null || true
wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="