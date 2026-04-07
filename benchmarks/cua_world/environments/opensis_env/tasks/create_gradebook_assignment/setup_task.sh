#!/bin/bash
set -e
echo "=== Setting up create_gradebook_assignment task ==="

# 1. Define DB Credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -B -e"

# 2. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 3. Ensure Services are running
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Wait for DB
for i in {1..10}; do
    if mysqladmin ping -u $DB_USER -p$DB_PASS --silent; then
        break
    fi
    sleep 1
done

# 4. Prepare Data: Ensure Course and Section Exist
echo "Preparing database state..."

# Create Course if not exists
$MYSQL_CMD "INSERT INTO courses (course_title, course_code, subject_id, school_id, credits, grade_level) VALUES ('General Science', 'SCI101', 1, 1, 1, 9) ON DUPLICATE KEY UPDATE course_title=VALUES(course_title);"

# Get Course ID
COURSE_ID=$($MYSQL_CMD "SELECT course_id FROM courses WHERE course_code='SCI101' LIMIT 1")

# Create Course Period (Section) assigned to Admin (staff_id=1)
# Note: In OpenSIS, staff_id 1 is usually the admin created by installer
$MYSQL_CMD "INSERT INTO course_periods (course_id, course_period_title, short_name, mp, meeting_days, period_id, teacher_id, room_id, total_seats, filled_seats, school_id, syear) VALUES ($COURSE_ID, 'General Science', 'SCI101-1', 'FY', 'MTWRF', 1, 1, 1, 30, 0, 1, 2025) ON DUPLICATE KEY UPDATE teacher_id=1;"

# Get Course Period ID for cleanup
CP_ID=$($MYSQL_CMD "SELECT course_period_id FROM course_periods WHERE course_id=$COURSE_ID AND period_id=1 LIMIT 1")

# 5. Clean Slate: Remove existing target data to prevent 'do nothing' success
# Remove Assignment if exists
$MYSQL_CMD "DELETE FROM gradebook_assignments WHERE course_period_id=$CP_ID AND title='Science Fair Project';"
# Remove Category if exists
$MYSQL_CMD "DELETE FROM gradebook_assignment_types WHERE course_period_id=$CP_ID AND title='Projects';"

echo "Clean slate established for Course Period ID: $CP_ID"

# 6. Launch Browser
echo "Launching Chrome..."
# Kill existing
pkill -f chrome 2>/dev/null || true

if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
else
    CHROME_CMD="chromium-browser"
fi

# Launch
su - ga -c "DISPLAY=:1 $CHROME_CMD --no-first-run --no-default-browser-check --password-store=basic --start-maximized http://localhost/opensis/ &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "chrome\|chromium"; then
        echo "Browser window detected"
        break
    fi
    sleep 1
done

# Focus and Maximize
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="