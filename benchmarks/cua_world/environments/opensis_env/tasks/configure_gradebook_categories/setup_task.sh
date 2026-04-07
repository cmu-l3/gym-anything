#!/bin/bash
set -e
echo "=== Setting up Configure Gradebook Categories Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME"

# Ensure services are running
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
sleep 2
systemctl start apache2 2>/dev/null || true
sleep 2

# 1. Setup Data: Teacher, Course, and Section
echo "Setting up database records..."

$MYSQL_CMD <<EOF
-- Ensure Teacher exists
INSERT INTO staff (first_name, last_name, profile, email) 
VALUES ('Alan', 'Turing', 'teacher', 'alan.turing@school.edu')
ON DUPLICATE KEY UPDATE profile='teacher';

SET @teacher_id = (SELECT staff_id FROM staff WHERE first_name='Alan' AND last_name='Turing' LIMIT 1);

-- Ensure Teacher Login exists
INSERT INTO login_authentication (user_id, profile_id, username, password)
VALUES (@teacher_id, 2, 'aturing', 'password123')
ON DUPLICATE KEY UPDATE username='aturing';

-- Ensure Course exists
INSERT INTO courses (course_title, course_short_name, grade_level, credits)
VALUES ('Mathematics 101', 'MATH101', '10', 1.0)
ON DUPLICATE KEY UPDATE course_title='Mathematics 101';

SET @course_id = (SELECT course_id FROM courses WHERE course_title='Mathematics 101' LIMIT 1);
SET @syear = (SELECT syear FROM schools WHERE id=1 LIMIT 1);

-- Ensure Course Period (Section) exists
INSERT INTO course_periods (course_id, syear, school_id, period_id, teacher_id, short_name, title, marking_period_id)
VALUES (@course_id, @syear, 1, 1, @teacher_id, '1', 'Period 1', 1)
ON DUPLICATE KEY UPDATE teacher_id=@teacher_id;

SET @cp_id = (SELECT course_period_id FROM course_periods WHERE course_id=@course_id AND period_id=1 LIMIT 1);

-- CRITICAL: Clear existing categories for this course period to ensure clean state
DELETE FROM gradebook_assignment_types WHERE course_period_id = @cp_id;

EOF

# 2. Browser Setup
echo "Starting browser..."
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true

if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser"
fi

# Start Chrome logged into OpenSIS
# Note: We rely on the agent to login, or we can pre-navigate to login page
nohup sudo -u ga $CHROME_CMD \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --no-sandbox \
    --disable-gpu \
    --window-size=1920,1080 \
    --password-store=basic \
    "http://localhost/opensis/" > /tmp/chrome.log 2>&1 &

# Wait for window
for i in {1..30}; do
    if wmctrl -l | grep -qi "chrome\|chromium"; then
        echo "Browser window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
wmctrl -a "Chrome" 2>/dev/null || wmctrl -a "Chromium" 2>/dev/null || true
wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 3. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="