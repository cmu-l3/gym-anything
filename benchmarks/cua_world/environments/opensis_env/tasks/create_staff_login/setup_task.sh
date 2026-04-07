#!/bin/bash
set -e
echo "=== Setting up Create Staff Login Task ==="

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
service mariadb start 2>/dev/null || systemctl start mariadb 2>/dev/null || true
service apache2 start 2>/dev/null || systemctl start apache2 2>/dev/null || true

# Wait for database
echo "Waiting for database..."
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# CLEANUP & PREP DATA
echo "Preparing database state..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
-- Delete user if exists
DELETE FROM login_authentication WHERE username='sconnor';

-- Delete staff if exists
DELETE FROM staff WHERE first_name='Sarah' AND last_name='Connor';

-- Reset Staff ID auto_increment if needed (optional, just ensuring clean state)

-- Insert UNLINKED Staff Member (Simulating HR entry)
-- Profile ID 2 is usually Teacher, but USER_ID being NULL means no login
INSERT INTO staff (first_name, last_name, gender, email, profile_id, current_school_id, USER_ID) 
VALUES ('Sarah', 'Connor', 'Female', 'sconnor@school.edu', 2, 1, NULL);
EOF

# Record initial staff count (for anti-gaming check: did they create a duplicate?)
INITIAL_STAFF_COUNT=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT COUNT(*) FROM staff;" 2>/dev/null)
echo "$INITIAL_STAFF_COUNT" > /tmp/initial_staff_count.txt
echo "Initial staff count: $INITIAL_STAFF_COUNT"

# START BROWSER
echo "Starting Chrome..."
pkill -f chrome 2>/dev/null || true

if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
else
    CHROME_CMD="chromium-browser"
fi

nohup sudo -u ga $CHROME_CMD \
    --no-first-run \
    --no-default-browser-check \
    --start-maximized \
    --password-store=basic \
    "http://localhost/opensis/" > /dev/null 2>&1 &

# Wait for window
for i in {1..30}; do
    if wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        break
    fi
    sleep 1
done

# Focus and Maximize
wmctrl -a "Chrome" 2>/dev/null || wmctrl -a "Chromium" 2>/dev/null || true
wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="