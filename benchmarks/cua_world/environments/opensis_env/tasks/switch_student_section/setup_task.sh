#!/bin/bash
set -e
echo "=== Setting up switch_student_section task ==="

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Wait for MariaDB
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
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME"

echo "Configuring database..."

# 1. Get School Details
# Ensure school exists
$MYSQL_CMD -e "INSERT IGNORE INTO schools (id, title, syear) VALUES (1, 'Demo School', 2025);"

SCHOOL_ID=1
SYEAR=$($MYSQL_CMD -N -e "SELECT syear FROM schools WHERE id=1 LIMIT 1" 2>/dev/null || echo "2025")
# Ensure marking period exists
$MYSQL_CMD -e "INSERT IGNORE INTO school_years (marking_period_id, syear, school_id, title, short_name, start_date, end_date) VALUES (1, $SYEAR, 1, 'Full Year', 'FY', '2024-08-01', '2025-06-30');"
MP_ID=1

echo "Using School: $SCHOOL_ID, SYear: $SYEAR, MP: $MP_ID"

# 2. Create Periods (Morning/Afternoon)
# We use REPLACE to ensure IDs are known or query them after
$MYSQL_CMD -e "DELETE FROM school_periods WHERE title IN ('Morning Session', 'Afternoon Session') AND school_id=$SCHOOL_ID;"
$MYSQL_CMD -e "INSERT INTO school_periods (school_id, syear, title, short_name, sort_order, length, start_time, end_time) VALUES ($SCHOOL_ID, $SYEAR, 'Morning Session', 'AM', 1, 120, '08:00:00', '10:00:00');"
$MYSQL_CMD -e "INSERT INTO school_periods (school_id, syear, title, short_name, sort_order, length, start_time, end_time) VALUES ($SCHOOL_ID, $SYEAR, 'Afternoon Session', 'PM', 2, 120, '13:00:00', '15:00:00');"

PER_AM_ID=$($MYSQL_CMD -N -e "SELECT period_id FROM school_periods WHERE title='Morning Session' AND school_id=$SCHOOL_ID ORDER BY period_id DESC LIMIT 1")
PER_PM_ID=$($MYSQL_CMD -N -e "SELECT period_id FROM school_periods WHERE title='Afternoon Session' AND school_id=$SCHOOL_ID ORDER BY period_id DESC LIMIT 1")

# 3. Create Course (Advanced Biology)
$MYSQL_CMD -e "INSERT IGNORE INTO courses (school_id, course_name, course_code, short_name, grade_level) VALUES ($SCHOOL_ID, 'Advanced Biology', 'SCI404', 'AdvBio', 12);"
COURSE_ID=$($MYSQL_CMD -N -e "SELECT course_id FROM courses WHERE course_code='SCI404' AND school_id=$SCHOOL_ID LIMIT 1")

# 4. Create Teacher
$MYSQL_CMD -e "INSERT IGNORE INTO staff (title, first_name, last_name, profile, profile_id) VALUES ('Dr.', 'Science', 'Teacher', 'teacher', 2);"
TEACHER_ID=$($MYSQL_CMD -N -e "SELECT staff_id FROM staff WHERE last_name='Teacher' AND first_name='Science' LIMIT 1")
$MYSQL_CMD -e "INSERT IGNORE INTO staff_school_relationship (staff_id, school_id, syear) VALUES ($TEACHER_ID, $SCHOOL_ID, $SYEAR);"

# 5. Create Course Sections (Schedule)
# Clean up existing sections for this course to ensure clean state
$MYSQL_CMD -e "DELETE FROM course_periods WHERE course_id=$COURSE_ID AND school_id=$SCHOOL_ID;"

$MYSQL_CMD <<EOF
INSERT INTO course_periods (syear, school_id, course_id, title, short_name, mp, period_id, teacher_id, total_seats, filled_seats) VALUES
($SYEAR, $SCHOOL_ID, $COURSE_ID, 'Adv Bio AM', 'BioAM', '$MP_ID', $PER_AM_ID, $TEACHER_ID, 20, 1),
($SYEAR, $SCHOOL_ID, $COURSE_ID, 'Adv Bio PM', 'BioPM', '$MP_ID', $PER_PM_ID, $TEACHER_ID, 20, 0);
EOF

CP_AM_ID=$($MYSQL_CMD -N -e "SELECT course_period_id FROM course_periods WHERE period_id=$PER_AM_ID AND course_id=$COURSE_ID LIMIT 1")
CP_PM_ID=$($MYSQL_CMD -N -e "SELECT course_period_id FROM course_periods WHERE period_id=$PER_PM_ID AND course_id=$COURSE_ID LIMIT 1")

# 6. Create Student (Emily Watson)
# Remove if exists to start fresh
$MYSQL_CMD -e "DELETE FROM students WHERE first_name='Emily' AND last_name='Watson';"
$MYSQL_CMD -e "INSERT INTO students (first_name, last_name, username, password, school_id, grade_level, is_active) VALUES ('Emily', 'Watson', 'ewatson', 'password', $SCHOOL_ID, 12, 'Y');"
STUDENT_ID=$($MYSQL_CMD -N -e "SELECT student_id FROM students WHERE first_name='Emily' AND last_name='Watson' LIMIT 1")

# Enroll student in school
$MYSQL_CMD -e "INSERT IGNORE INTO student_enrollment (student_id, school_id, syear, grade_id, start_date, enrollment_code) VALUES ($STUDENT_ID, $SCHOOL_ID, $SYEAR, 4, '2024-09-01', 1);"

# 7. Enroll Student in Morning Section (Initial State)
# Start date is 30 days ago
START_DATE=$(date -d "30 days ago" +%Y-%m-%d)
$MYSQL_CMD -e "DELETE FROM schedule WHERE student_id=$STUDENT_ID;"
$MYSQL_CMD <<EOF
INSERT INTO schedule (syear, school_id, student_id, start_date, marking_period_id, course_id, course_period_id, scheduler_lock) VALUES
($SYEAR, $SCHOOL_ID, $STUDENT_ID, '$START_DATE', '$MP_ID', $COURSE_ID, $CP_AM_ID, 'N');
EOF

# Save IDs for verification export
cat > /tmp/task_config.json <<EOF
{
  "student_id": $STUDENT_ID,
  "course_id": $COURSE_ID,
  "cp_am_id": $CP_AM_ID,
  "cp_pm_id": $CP_PM_ID,
  "teacher_id": $TEACHER_ID
}
EOF

echo "Setup Complete: Student $STUDENT_ID enrolled in AM Section ($CP_AM_ID). PM Section is $CP_PM_ID."

# Open Browser
if command -v google-chrome-stable &> /dev/null; then
    CHROME="google-chrome-stable"
else
    CHROME="chromium-browser"
fi

if ! pgrep -f "chrome" > /dev/null; then
    su - ga -c "DISPLAY=:1 $CHROME --start-maximized --no-sandbox http://localhost/opensis/ &"
    sleep 5
fi

# Maximize
DISPLAY=:1 wmctrl -r "OpenSIS" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true