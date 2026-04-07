#!/bin/bash
set -e
echo "=== Setting up Update Staff Profile task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
sleep 2
systemctl start apache2 2>/dev/null || true
sleep 2

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p'$DB_PASS' $DB_NAME"

# Determine current SYEAR from schools table
SYEAR=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -e "SELECT syear FROM schools WHERE id=1 LIMIT 1" 2>/dev/null || echo "2025")
echo "Using SYEAR=$SYEAR"

# Clean up any existing Robert Thompson records to ensure a fresh start
echo "Cleaning up any existing Robert Thompson records..."
mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -e "
DELETE la FROM login_authentication la
  INNER JOIN staff s ON la.user_id = s.staff_id AND la.profile_id = 2
  WHERE s.first_name = 'Robert' AND s.last_name = 'Thompson';
DELETE FROM staff_school_relationship WHERE staff_id IN (SELECT staff_id FROM staff WHERE first_name='Robert' AND last_name='Thompson');
DELETE FROM staff_school_info WHERE staff_id IN (SELECT staff_id FROM staff WHERE first_name='Robert' AND last_name='Thompson');
DELETE FROM staff WHERE first_name='Robert' AND last_name='Thompson';
" 2>/dev/null || true

# Find next available staff_id
NEXT_STAFF_ID=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -e "SELECT COALESCE(MAX(staff_id),1)+1 FROM staff" 2>/dev/null || echo "10")
echo "Using staff_id=$NEXT_STAFF_ID for Robert Thompson"

# Insert the teacher with known INITIAL values
# Title: Mr., Email: r.thompson@oldschool.edu
echo "Creating teacher Robert Thompson with initial values..."
mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -e "
INSERT INTO staff (staff_id, current_school_id, title, first_name, last_name, email, profile, profile_id)
VALUES ($NEXT_STAFF_ID, 1, 'Mr.', 'Robert', 'Thompson', 'r.thompson@oldschool.edu', 'teacher', 2);

-- Ensure teacher profile exists
INSERT INTO user_profiles (id, profile, title) VALUES (2, 'teacher', 'Teacher')
ON DUPLICATE KEY UPDATE profile='teacher';

-- Link staff to school
INSERT INTO staff_school_info (staff_id, category, home_school, opensis_access, opensis_profile, school_access)
VALUES ($NEXT_STAFF_ID, 'Teacher', 1, 'Y', 'teacher', 'Y')
ON DUPLICATE KEY UPDATE opensis_access='Y';

-- Staff school relationship
INSERT INTO staff_school_relationship (staff_id, school_id, syear)
VALUES ($NEXT_STAFF_ID, 1, $SYEAR)
ON DUPLICATE KEY UPDATE syear=$SYEAR;

-- Add USER_ID column if not exists (schema compatibility)
ALTER TABLE staff ADD COLUMN IF NOT EXISTS USER_ID int(11) DEFAULT NULL;
UPDATE staff SET USER_ID = $NEXT_STAFF_ID WHERE staff_id = $NEXT_STAFF_ID;

-- Add profile exceptions for the teacher module visibility so admin can manage them
INSERT INTO profile_exceptions (profile_id, modname, can_use, can_edit)
VALUES (1, 'users/User.php', 'Y', 'Y'),
       (1, 'users/User.php&category_id=2', 'Y', 'Y'),
       (1, 'users/User.php&staff_id=new&category_id=2', 'Y', 'Y'),
       (1, 'users/AddStaff.php', 'Y', 'Y'),
       (1, 'users/StaffInfo.php', 'Y', 'Y')
ON DUPLICATE KEY UPDATE can_use='Y', can_edit='Y';
" 2>/dev/null

# Record initial state for anti-gaming verification
echo "Recording initial state..."
INITIAL_TITLE="Mr."
INITIAL_EMAIL="r.thompson@oldschool.edu"
echo "$INITIAL_TITLE" > /tmp/initial_staff_title.txt
echo "$INITIAL_EMAIL" > /tmp/initial_staff_email.txt

# Kill any existing browser instances
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true
sleep 2

# Start Chrome pointing to OpenSIS login
echo "Launching Chrome..."
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

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i -E "chrome|chromium|opensis"; then
        echo "  Chrome window detected"
        break
    fi
    sleep 1
done

sleep 2

# Maximize Chrome window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Take screenshot of initial state
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="