#!/bin/bash
set -e
echo "=== Setting up create_parent_portal_account task ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Ensure OpenSIS services are running
echo "Checking services..."
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Wait for database
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# 3. Database Credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# 4. Prepare Data
echo "Preparing database state..."

# Get current school year
SYEAR=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "SELECT syear FROM schools WHERE id=1 LIMIT 1" 2>/dev/null || echo "2025")

# Ensure Student 'Kevin Chen' exists
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" << STUDENT_SQL
-- Insert student Kevin Chen if not exists
INSERT INTO students (first_name, last_name, middle_name, date_of_birth, gender, grade_id, current_school_id, email)
SELECT 'Kevin', 'Chen', 'J', '2007-03-15', 'Male', 
    (SELECT id FROM school_gradelevels WHERE school_id=1 AND short_name='10' LIMIT 1),
    1, 'kevin.chen@school.edu'
FROM DUAL
WHERE NOT EXISTS (
    SELECT 1 FROM students WHERE first_name='Kevin' AND last_name='Chen'
);

-- Get the student_id
SET @kevin_id = (SELECT student_id FROM students WHERE first_name='Kevin' AND last_name='Chen' LIMIT 1);

-- Enroll the student if not already enrolled
INSERT IGNORE INTO student_enrollment (student_id, syear, school_id, grade_id, start_date, enrollment_code)
SELECT @kevin_id, $SYEAR, 1,
    (SELECT id FROM school_gradelevels WHERE school_id=1 AND short_name='10' LIMIT 1),
    '${SYEAR}-08-15', 'NEW'
FROM DUAL
WHERE @kevin_id IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM student_enrollment WHERE student_id=@kevin_id AND syear=$SYEAR
);
STUDENT_SQL

# Capture Kevin's ID for verification
KEVIN_ID=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "SELECT student_id FROM students WHERE first_name='Kevin' AND last_name='Chen' LIMIT 1" 2>/dev/null)
echo "$KEVIN_ID" > /tmp/kevin_id.txt

# Clean up any existing 'Margaret Chen' or 'mchen_parent' to ensure fresh task
echo "Cleaning up old data..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "DELETE FROM login_authentication WHERE username='mchen_parent';" 2>/dev/null || true
# Note: User details might be in 'staff' or 'users' depending on version, try to clean broadly if possible, 
# but relying on username uniqueness is usually sufficient for 'login_authentication'.
# We will also try to remove by name from staff if possible to avoid duplicates.
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "DELETE FROM staff WHERE first_name='Margaret' AND last_name='Chen' AND profile='Parent';" 2>/dev/null || true

# Record initial count of parent accounts (Profile ID 4 is typically Parent)
INITIAL_PARENT_COUNT=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e "SELECT COUNT(*) FROM login_authentication WHERE profile_id=4" 2>/dev/null || echo "0")
echo "$INITIAL_PARENT_COUNT" > /tmp/initial_parent_count.txt

# 5. Launch Browser
echo "Launching browser..."
# Kill existing
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true

if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser"
fi

su - ga -c "DISPLAY=:1 $CHROME_CMD --no-sandbox --disable-gpu --window-size=1920,1080 --start-maximized http://localhost/opensis/ &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        break
    fi
    sleep 1
done

# Maximize explicitly
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Capture Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="