#!/bin/bash
set -e
echo "=== Setting up Enter Historical Transcript Record task ==="

# Source shared utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure services are running
echo "Checking services..."
service mariadb start 2>/dev/null || systemctl start mariadb 2>/dev/null || true
service apache2 start 2>/dev/null || systemctl start apache2 2>/dev/null || true

# Wait for DB
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "Database is ready."
        break
    fi
    sleep 1
done

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# SQL Helper
run_sql() {
    mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "$1" 2>/dev/null
}

echo "Preparing student data..."

# 1. Ensure Student 'Leo Vance' exists
# We use INSERT IGNORE or ON DUPLICATE KEY to be idempotent
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
INSERT INTO students (first_name, last_name, gender, date_of_birth, grade_level, is_disable)
SELECT 'Leo', 'Vance', 'Male', '2007-04-12', '10', 'N'
WHERE NOT EXISTS (
    SELECT 1 FROM students WHERE first_name='Leo' AND last_name='Vance'
);
EOF

# Get Student ID
STUDENT_ID=$(run_sql "SELECT student_id FROM students WHERE first_name='Leo' AND last_name='Vance' LIMIT 1")
echo "Student ID for Leo Vance: $STUDENT_ID"

if [ -z "$STUDENT_ID" ]; then
    echo "ERROR: Failed to create/find student."
    exit 1
fi

# 2. CLEANUP: Ensure the target transcript record does NOT exist yet
# We delete any Biology grades for this student to ensure a clean start
echo "Cleaning up any existing Biology records for this student..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
DELETE FROM student_mp_grades 
WHERE student_id = '$STUDENT_ID' 
AND (course_name LIKE '%Biology%' OR comment LIKE '%Biology%');

DELETE FROM student_report_card_grades
WHERE student_id = '$STUDENT_ID'
AND (course_name LIKE '%Biology%' OR comment LIKE '%Biology%');
EOF

# 3. Setup Browser
echo "Configuring browser..."
# Kill any existing Chrome/Firefox
pkill -f chrome 2>/dev/null || true
pkill -f firefox 2>/dev/null || true

# Launch Chrome to OpenSIS login
if [ -f /usr/bin/google-chrome ]; then
    BROWSER="/usr/bin/google-chrome"
elif [ -f /usr/bin/chromium ]; then
    BROWSER="/usr/bin/chromium"
else
    BROWSER="google-chrome-stable"
fi

# Launch in background as user 'ga'
su - ga -c "DISPLAY=:1 $BROWSER --no-sandbox --start-maximized --disable-gpu http://localhost/opensis/ &"

# Wait for window
echo "Waiting for browser window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Chrome\|Chromium\|OpenSIS"; then
        echo "Browser detected."
        break
    fi
    sleep 1
done

# Focus and Maximize
DISPLAY=:1 wmctrl -a "OpenSIS" 2>/dev/null || true
DISPLAY=:1 wmctrl -r ":ACTIVE:" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 4. Initial Screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="