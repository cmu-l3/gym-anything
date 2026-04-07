#!/bin/bash
set -e
echo "=== Setting up add_student_medical_alert task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure services are running
service mariadb start || true
service apache2 start || true

# Wait for DB
for i in {1..30}; do
    if mysqladmin ping --silent; then
        break
    fi
    sleep 1
done

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# 1. Create the specific student (Sarah Connor)
# We delete first to ensure a clean state
echo "Preparing student data..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
DELETE FROM students WHERE first_name='Sarah' AND last_name='Connor';
DELETE FROM student_medical WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Sarah' AND last_name='Connor');

-- Insert Student
INSERT INTO students (first_name, last_name, grade_level, username, password, is_active, enrollment_date)
VALUES ('Sarah', 'Connor', '10', 'sconnor', 'password', 'Y', CURDATE());

-- Get the ID we just created
SET @sid = LAST_INSERT_ID();

-- Create enrollment record (needed for search visibility in some OpenSIS versions)
INSERT INTO student_enrollment (student_id, school_id, syear, grade_id, start_date, enrollment_code)
SELECT @sid, 1, (SELECT syear FROM schools LIMIT 1), 2, CURDATE(), '1' 
FROM DUAL WHERE EXISTS (SELECT 1 FROM schools);
EOF

# 2. Record initial count of medical records for this student (should be 0)
# We'll need the student ID for this
STUDENT_ID=$(mysql -N -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT student_id FROM students WHERE first_name='Sarah' AND last_name='Connor' LIMIT 1")
echo "$STUDENT_ID" > /tmp/target_student_id.txt

if [ -n "$STUDENT_ID" ]; then
    INITIAL_COUNT=$(mysql -N -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT COUNT(*) FROM student_medical WHERE student_id=$STUDENT_ID" 2>/dev/null || echo "0")
    echo "$INITIAL_COUNT" > /tmp/initial_medical_count.txt
else
    echo "0" > /tmp/initial_medical_count.txt
    echo "WARNING: Could not retrieve new student ID"
fi

# 3. Prepare Browser
echo "Launching browser..."
if ! pgrep -f "chrome" > /dev/null; then
    su - ga -c "DISPLAY=:1 google-chrome-stable --no-sandbox --disable-gpu --start-maximized http://localhost/opensis &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Chrome"; then
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="