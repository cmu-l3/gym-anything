#!/bin/bash
set -e
echo "=== Setting up drop_student_course task ==="

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure MySQL/MariaDB is running
service mariadb start 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Database connection details
DB_NAME="opensis"
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME"

# Function to execute SQL safely
run_sql() {
    $MYSQL_CMD -e "$1" 2>/dev/null
}

echo "Step 1: preparing database data..."

# Determine current School Year (SYEAR) and School ID
SYEAR=$(run_sql "SELECT syear FROM schools WHERE id=1 LIMIT 1;" -N)
if [ -z "$SYEAR" ]; then SYEAR=2025; fi
SCHOOL_ID=1

echo "Using SYEAR=$SYEAR, SCHOOL_ID=$SCHOOL_ID"

# 1. Create Student: Philip Williams
# We use a subquery check to avoid duplicates, but UPDATE to ensure properties are correct
run_sql "
INSERT INTO students (student_id, first_name, last_name, middle_name, gender, date_of_birth, grade_level)
SELECT COALESCE(MAX(student_id), 0)+1, 'Philip', 'Williams', 'J', 'M', '2005-09-15', '10'
FROM students
WHERE NOT EXISTS (SELECT 1 FROM students WHERE first_name='Philip' AND last_name='Williams');
"

# Get Philip's ID
PHILIP_ID=$(run_sql "SELECT student_id FROM students WHERE first_name='Philip' AND last_name='Williams' LIMIT 1;" -N)
echo "Student ID: $PHILIP_ID"

# Ensure Philip is enrolled in the school (required to schedule)
run_sql "
INSERT INTO student_enrollment (student_id, syear, school_id, grade_id, start_date, enrollment_code)
VALUES ($PHILIP_ID, $SYEAR, $SCHOOL_ID, 2, '${SYEAR}-08-15', 'NEW')
ON DUPLICATE KEY UPDATE syear=$SYEAR;
"

# 2. Create Course: Introduction to Psychology
run_sql "
INSERT INTO courses (course_id, syear, school_id, title, short_name, subject_area, credits, grade_level)
SELECT COALESCE(MAX(course_id), 0)+1, $SYEAR, $SCHOOL_ID, 'Introduction to Psychology', 'PSY101', 'Social Sciences', 1.0, '10'
FROM courses
WHERE NOT EXISTS (SELECT 1 FROM courses WHERE short_name='PSY101' AND syear=$SYEAR);
"

COURSE_ID=$(run_sql "SELECT course_id FROM courses WHERE short_name='PSY101' AND syear=$SYEAR LIMIT 1;" -N)
echo "Course ID: $COURSE_ID"

# 3. Create Course Period (Section)
# Marking period 1 (FY - Full Year) usually exists by default
run_sql "
INSERT INTO course_periods (course_period_id, syear, school_id, course_id, title, short_name, marking_period_id, mp, begin_date, end_date, total_seats, filled_seats)
SELECT COALESCE(MAX(course_period_id), 0)+1, $SYEAR, $SCHOOL_ID, $COURSE_ID, 'PSY101 - Section 1', 'PSY101-1', 1, 'FY', '${SYEAR}-08-01', '${SYEAR}-06-30', 30, 0
FROM course_periods
WHERE NOT EXISTS (SELECT 1 FROM course_periods WHERE short_name='PSY101-1' AND syear=$SYEAR);
"

CP_ID=$(run_sql "SELECT course_period_id FROM course_periods WHERE short_name='PSY101-1' AND syear=$SYEAR LIMIT 1;" -N)
echo "Course Period ID: $CP_ID"

# 4. Schedule Philip into PSY101 (The target to be dropped)
# Check if already scheduled
IS_SCHEDULED=$(run_sql "SELECT COUNT(*) FROM schedule WHERE student_id=$PHILIP_ID AND course_period_id=$CP_ID;" -N)

if [ "$IS_SCHEDULED" -eq "0" ]; then
    echo "Scheduling student..."
    run_sql "
    INSERT INTO schedule (student_id, course_period_id, syear, school_id, start_date, marking_period_id, mp)
    VALUES ($PHILIP_ID, $CP_ID, $SYEAR, $SCHOOL_ID, '${SYEAR}-08-15', 1, 'FY');
    "
fi

# Record initial count of schedule records for Philip (should be >= 1)
INITIAL_COUNT=$(run_sql "SELECT COUNT(*) FROM schedule WHERE student_id=$PHILIP_ID;" -N)
echo "$INITIAL_COUNT" > /tmp/initial_schedule_count.txt
echo "Initial schedule count for Philip: $INITIAL_COUNT"

# Save IDs for export verification
echo "$PHILIP_ID" > /tmp/target_student_id.txt
echo "$CP_ID" > /tmp/target_cp_id.txt
echo "$COURSE_ID" > /tmp/target_course_id.txt

# Step 2: Prepare UI
echo "Step 2: Preparing browser..."

# Kill existing Chrome
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true

# Start Chrome logged in (Session persistence handled by browser profile or manual login script if needed)
# For this env, we assume the agent logs in or uses saved session. 
# We'll launch the login page.
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
else
    CHROME_CMD="chromium-browser"
fi

su - ga -c "DISPLAY=:1 $CHROME_CMD \
    --no-first-run \
    --no-default-browser-check \
    --start-maximized \
    --disable-infobars \
    --password-store=basic \
    http://localhost/opensis/ &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="