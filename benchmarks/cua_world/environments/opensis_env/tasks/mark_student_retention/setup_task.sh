#!/bin/bash
set -e
echo "=== Setting up Mark Student Retention Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
if ! systemctl is-active --quiet mariadb; then
    echo "Starting MariaDB..."
    systemctl start mariadb
    sleep 3
fi
if ! systemctl is-active --quiet apache2; then
    echo "Starting Apache..."
    systemctl start apache2
    sleep 2
fi

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# 1. Ensure the target student exists
# We verify if he exists, if not we insert him.
# If he exists, we RESET his retention status to ensure he isn't already retained.
echo "Preparing student record..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
-- Insert student if not exists
INSERT INTO students (
    first_name, last_name, username, password, 
    grade_level, gender, date_of_birth, email, 
    is_active, enrollment_date
) 
SELECT 
    'Robert', 'Failson', 'rfailson', 'Student123',
    '9', 'Male', '2008-04-15', 'robert.failson@example.com',
    'Y', CURDATE()
WHERE NOT EXISTS (
    SELECT 1 FROM students WHERE first_name='Robert' AND last_name='Failson'
);

-- Reset enrollment options (clean state)
-- Attempt to reset rolling_option in students table (if it exists there)
UPDATE students 
SET rolling_option = NULL, next_school = 0, next_grade_id = 0
WHERE first_name='Robert' AND last_name='Failson';

-- Attempt to reset in student_enrollment table (if schema uses separate table)
-- We use IGNORE to prevent errors if table/column doesn't match perfectly
UPDATE IGNORE student_enrollment 
SET rolling_option = NULL, next_school = 0
WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Robert' AND last_name='Failson');
EOF

# Record initial state of the student for verification
echo "Recording initial state..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -B -e \
    "SELECT student_id, first_name, rolling_option FROM students WHERE first_name='Robert' AND last_name='Failson'" \
    > /tmp/initial_student_state.txt 2>/dev/null || true

# 2. Setup Browser
# Kill any existing Chrome
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true
sleep 1

# Start Chrome on OpenSIS Login
echo "Launching Chrome..."
OPENSIS_URL="http://localhost/opensis/"

if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser"
fi

# Run as ga user
su - ga -c "DISPLAY=:1 $CHROME_CMD --no-sandbox --start-maximized --no-first-run '$OPENSIS_URL' &"
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        echo "Browser window detected"
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# Capture initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="