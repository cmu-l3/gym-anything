#!/bin/bash
set -e
echo "=== Setting up task: add_student_address ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure Database and Web Server are running
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Wait for MariaDB to be ready
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
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME"

# 4. Determine School Year (SYEAR)
# Get current SYEAR from schools table or calculate it
SYEAR=$($MYSQL_CMD -N -B -e "SELECT syear FROM schools WHERE id=1 LIMIT 1" 2>/dev/null)
if [ -z "$SYEAR" ]; then
    CURRENT_MONTH=$(date +%m)
    CURRENT_YEAR=$(date +%Y)
    if [ "$CURRENT_MONTH" -ge 8 ]; then
        SYEAR=$((CURRENT_YEAR + 1))
    else
        SYEAR=$CURRENT_YEAR
    fi
fi
echo "Using SYEAR: $SYEAR"

# 5. Get Grade 10 ID
GRADE10_ID=$($MYSQL_CMD -N -B -e "SELECT id FROM school_gradelevels WHERE short_name='10' AND school_id=1 LIMIT 1" 2>/dev/null)
if [ -z "$GRADE10_ID" ]; then GRADE10_ID=2; fi

# 6. Prepare Student Data (Alondra Reyes)
# First, remove if exists to ensure clean state
EXISTING_ID=$($MYSQL_CMD -N -B -e "SELECT student_id FROM students WHERE first_name='Alondra' AND last_name='Reyes' LIMIT 1" 2>/dev/null)

if [ -n "$EXISTING_ID" ]; then
    echo "Removing existing student record (ID: $EXISTING_ID)..."
    $MYSQL_CMD -e "DELETE FROM student_enrollment WHERE student_id=$EXISTING_ID" 2>/dev/null || true
    $MYSQL_CMD -e "DELETE FROM address WHERE student_id=$EXISTING_ID" 2>/dev/null || true
    $MYSQL_CMD -e "DELETE FROM students_join_address WHERE student_id=$EXISTING_ID" 2>/dev/null || true
    $MYSQL_CMD -e "DELETE FROM students WHERE student_id=$EXISTING_ID" 2>/dev/null || true
fi

# Find next ID
NEXT_ID=$($MYSQL_CMD -N -B -e "SELECT COALESCE(MAX(student_id), 0) + 1 FROM students" 2>/dev/null)

echo "Creating student Alondra Reyes (ID: $NEXT_ID)..."

# Insert Student
$MYSQL_CMD -e "
INSERT INTO students (student_id, first_name, last_name, middle_name, gender, dob, ethnicity, current_school_id)
VALUES ($NEXT_ID, 'Alondra', 'Reyes', 'M', 'Female', '2008-07-14', 'Hispanic/Latino', 1);
"

# Insert Enrollment
$MYSQL_CMD -e "
INSERT INTO student_enrollment (student_id, school_id, syear, grade_id, start_date, enrollment_code)
VALUES ($NEXT_ID, 1, $SYEAR, $GRADE10_ID, CURDATE(), 'New');
"

# 7. Record initial address count (Should be 0)
INITIAL_ADDR_COUNT=$($MYSQL_CMD -N -B -e "
SELECT COUNT(*) FROM address WHERE student_id=$NEXT_ID
UNION ALL
SELECT COUNT(*) FROM students_join_address WHERE student_id=$NEXT_ID
" 2>/dev/null | head -1 || echo "0")
echo "$INITIAL_ADDR_COUNT" > /tmp/initial_address_count.txt
echo "$NEXT_ID" > /tmp/target_student_id.txt

echo "Student created. Initial address count: $INITIAL_ADDR_COUNT"

# 8. Setup Browser
# Kill existing Chrome
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true
sleep 1

# Launch Chrome
echo "Launching Chrome..."
su - ga -c "DISPLAY=:1 google-chrome-stable \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --no-first-run \
    --no-default-browser-check \
    --disable-infobars \
    --password-store=basic \
    --start-maximized \
    'http://localhost/opensis/' &" 2>/dev/null

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "chrome|chromium|opensis"; then
        echo "Browser window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# 9. Capture Initial Screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="