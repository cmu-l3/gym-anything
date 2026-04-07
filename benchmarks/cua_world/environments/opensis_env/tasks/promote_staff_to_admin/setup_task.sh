#!/bin/bash
set -euo pipefail

echo "=== Setting up Promote Staff Task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure services are running
service mariadb start 2>/dev/null || systemctl start mariadb 2>/dev/null || true
service apache2 start 2>/dev/null || systemctl start apache2 2>/dev/null || true

# Wait for database to be ready
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "Database is ready."
        break
    fi
    sleep 1
done

# Database Credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME"

echo "Step 1: Preparing Data - Resetting Sarah Jenkins..."

# Remove Sarah Jenkins if she exists to ensure clean state
$MYSQL_CMD -e "
DELETE FROM staff_school_relationship WHERE staff_id IN (SELECT staff_id FROM staff WHERE first_name='Sarah' AND last_name='Jenkins');
DELETE FROM staff_school_info WHERE staff_id IN (SELECT staff_id FROM staff WHERE first_name='Sarah' AND last_name='Jenkins');
DELETE FROM login_authentication WHERE user_id IN (SELECT staff_id FROM staff WHERE first_name='Sarah' AND last_name='Jenkins');
DELETE FROM staff WHERE first_name='Sarah' AND last_name='Jenkins';
" 2>/dev/null || true

# Determine current School Year
SYEAR=$($MYSQL_CMD -N -e "SELECT syear FROM schools WHERE id=1 LIMIT 1" 2>/dev/null || echo "2025")
echo "Using SYEAR=$SYEAR"

# Insert Sarah Jenkins as a TEACHER (Profile ID 2)
# Using a fixed ID (e.g., 9001) to verify specific record later
$MYSQL_CMD <<EOF
-- Insert Staff Record
INSERT INTO staff (staff_id, current_school_id, title, first_name, last_name, email, gender, profile, profile_id) 
VALUES (9001, 1, 'Ms.', 'Sarah', 'Jenkins', 's.jenkins@demoschool.edu', 'Female', 'Teacher', 2);

-- Update USER_ID mapping
UPDATE staff SET USER_ID = 9001 WHERE staff_id = 9001;

-- Insert Staff School Info (Profile: Teacher)
INSERT INTO staff_school_info (staff_id, category, home_school, opensis_access, opensis_profile, school_access) 
VALUES (9001, 'Teacher', 1, 'Y', 'teacher', 'Y');

-- Insert School Relationship
INSERT INTO staff_school_relationship (staff_id, school_id, syear) 
VALUES (9001, 1, $SYEAR);

-- Insert Login Auth (Profile ID 2 = Teacher)
INSERT INTO login_authentication (user_id, profile_id, username, password, last_login) 
VALUES (9001, 2, 'sjenkins', 'Teacher@123', NOW());
EOF

echo "Data preparation complete. Sarah Jenkins (ID 9001) created as Teacher."

# Record initial state for verification
INITIAL_PROFILE=$($MYSQL_CMD -N -e "SELECT profile_id FROM login_authentication WHERE user_id=9001" 2>/dev/null || echo "0")
echo "$INITIAL_PROFILE" > /tmp/initial_profile_id.txt

# Browser Setup
echo "Step 2: Launching Browser..."
# Kill any existing Chrome instances
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true

# Launch Chrome
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser"
fi

# Start browser maximized pointing to OpenSIS
nohup sudo -u ga $CHROME_CMD \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --no-sandbox \
    --disable-gpu \
    --window-size=1920,1080 \
    --start-maximized \
    --password-store=basic \
    "http://localhost/opensis/" > /tmp/chrome_launch.log 2>&1 &

# Wait for window
for i in {1..30}; do
    if wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        echo "Browser window detected."
        break
    fi
    sleep 1
done

# Ensure window is focused and maximized
wmctrl -a "Chrome" 2>/dev/null || wmctrl -a "Chromium" 2>/dev/null || true
wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Capture initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="