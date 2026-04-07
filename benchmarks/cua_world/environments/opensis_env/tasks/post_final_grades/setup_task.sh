#!/bin/bash
set -e

echo "=== Setting up post_final_grades task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Ensure services are running
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true
sleep 3

# Wait for MySQL
for i in {1..30}; do
    if mysqladmin ping -u $DB_USER -p$DB_PASS --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

echo "Configuring database state..."

# SQL Setup:
# 1. Update School Year/Marking Period to be open for grading NOW
# 2. Create Course "World History"
# 3. Create Teacher (or use admin)
# 4. Create Section (Period 1)
# 5. Create Students
# 6. Enroll Students
# 7. Clean up any existing grades for this specific setup

CURRENT_DATE=$(date +%Y-%m-%d)
CURRENT_YEAR=$(date +%Y)
SYEAR=$CURRENT_YEAR

mysql -u $DB_USER -p$DB_PASS $DB_NAME <<EOF
-- 1. Ensure Marking Period is open
UPDATE school_years 
SET start_date = DATE_SUB(CURDATE(), INTERVAL 4 MONTH),
    end_date = DATE_ADD(CURDATE(), INTERVAL 4 MONTH)
WHERE school_id = 1;

-- Update or insert marking period (FY) to ensure it's active
UPDATE school_years
SET does_grades='Y', does_comments='Y'
WHERE school_id=1;

-- 2. Ensure Grading Scale exists (Standard A-F)
-- (OpenSIS usually installs with this, but ensuring 'A', 'B', 'C' exist)

-- 3. Create Course 'World History'
DELETE FROM courses WHERE title = 'World History';
INSERT INTO courses (syear, school_id, title, short_name, grade_level, credits)
VALUES ($SYEAR, 1, 'World History', 'HIST101', '10', 1.0);

SET @course_id = LAST_INSERT_ID();

-- 4. Get Admin Staff ID (usually 1)
SET @staff_id = (SELECT staff_id FROM staff WHERE profile='admin' LIMIT 1);

-- 5. Create Course Period (Section) - Period 1
-- Note: 'course_periods' table structure varies slightly by version, 
-- assuming standard columns based on env analysis
INSERT INTO course_periods (syear, school_id, course_id, title, short_name, teacher_id, marking_period_id)
VALUES ($SYEAR, 1, @course_id, 'Period 1', 'P1', @staff_id, 1);

SET @cp_id = LAST_INSERT_ID();
-- Save cp_id for verification later if needed
SELECT @cp_id INTO OUTFILE '/tmp/course_period_id.txt';

-- 6. Create Students
-- Clean up if they exist
DELETE FROM students WHERE first_name IN ('James', 'Sarah', 'Robert') AND last_name IN ('Miller', 'Wilson', 'Chen');

INSERT INTO students (syear, school_id, first_name, last_name, username, password, grade_level, is_disable) VALUES
($SYEAR, 1, 'James', 'Miller', 'jmiller', 'password', '10', 'N'),
($SYEAR, 1, 'Sarah', 'Wilson', 'swilson', 'password', '10', 'N'),
($SYEAR, 1, 'Robert', 'Chen', 'rchen', 'password', '10', 'N');

-- 7. Enroll Students in the Course Section
-- Get IDs
SET @s1 = (SELECT student_id FROM students WHERE first_name='James' AND last_name='Miller' LIMIT 1);
SET @s2 = (SELECT student_id FROM students WHERE first_name='Sarah' AND last_name='Wilson' LIMIT 1);
SET @s3 = (SELECT student_id FROM students WHERE first_name='Robert' AND last_name='Chen' LIMIT 1);

-- Enroll (schedule table)
INSERT INTO schedule (syear, school_id, student_id, course_id, course_period_id, marking_period_id, start_date) VALUES
($SYEAR, 1, @s1, @course_id, @cp_id, 1, DATE_SUB(CURDATE(), INTERVAL 3 MONTH)),
($SYEAR, 1, @s2, @course_id, @cp_id, 1, DATE_SUB(CURDATE(), INTERVAL 3 MONTH)),
($SYEAR, 1, @s3, @course_id, @cp_id, 1, DATE_SUB(CURDATE(), INTERVAL 3 MONTH));

-- 8. Clean existing grades for these students in this course (Anti-gaming prep)
DELETE FROM student_report_card_grades 
WHERE course_period_id = @cp_id;

EOF

# Setup Chrome/Browser state
# Kill existing
pkill -f chrome 2>/dev/null || true
sleep 1

# Start Chrome logged in (automation script usually handles login, but we'll start at login page)
if command -v google-chrome-stable &> /dev/null; then
    CHROME="google-chrome-stable"
else
    CHROME="chromium-browser"
fi

su - ga -c "DISPLAY=:1 $CHROME --no-sandbox --start-maximized http://localhost/opensis/ &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenSIS"; then
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "OpenSIS" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="