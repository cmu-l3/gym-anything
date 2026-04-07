#!/bin/bash
set -e
echo "=== Setting up batch_assign_homeroom ==="

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Start Services
systemctl start mariadb || true
systemctl start apache2 || true

# Wait for DB
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent; then
        break
    fi
    sleep 1
done

# 3. Prepare Database State
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Ensure 'homeroom' column exists in students table for this task context
# (Making task robust against schema variations)
mysql -u $DB_USER -p$DB_PASS $DB_NAME -e "
ALTER TABLE students ADD COLUMN IF NOT EXISTS homeroom VARCHAR(100) DEFAULT NULL;
" 2>/dev/null || true

# Create Room 101 in school_rooms
mysql -u $DB_USER -p$DB_PASS $DB_NAME -e "
INSERT INTO school_rooms (school_id, title, capacity, description) 
VALUES (1, 'Room 101', 30, 'Homeroom 101') 
ON DUPLICATE KEY UPDATE title='Room 101';
"

# Get max ID to identify new students
MAX_ID=$(mysql -N -u $DB_USER -p$DB_PASS $DB_NAME -e "SELECT MAX(student_id) FROM students;")
MAX_ID=${MAX_ID:-0}

# Insert Target Students (Jason, Ashley, Michael)
# We set them to Grade 9, Active
echo "Creating target students..."
mysql -u $DB_USER -p$DB_PASS $DB_NAME <<EOF
INSERT INTO students (first_name, last_name, grade_level, is_active, enrollment_code, school_id, homeroom)
VALUES 
('Jason', 'Miller', '9', 'Y', '1', 1, NULL),
('Ashley', 'Davis', '9', 'Y', '1', 1, NULL),
('Michael', 'Wilson', '9', 'Y', '1', 1, NULL);
EOF

# Save the IDs of the students we just created for verification
mysql -N -u $DB_USER -p$DB_PASS $DB_NAME -e "
SELECT student_id, first_name, last_name 
FROM students 
WHERE student_id > $MAX_ID 
ORDER BY student_id ASC;
" > /tmp/target_students.txt

echo "Target students created:"
cat /tmp/target_students.txt

# 4. Browser Setup
# Kill existing Chrome
pkill -f chrome 2>/dev/null || true
sleep 1

# Start Chrome
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
else
    CHROME_CMD="chromium-browser"
fi

nohup sudo -u ga $CHROME_CMD \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --no-sandbox \
    --disable-gpu \
    --window-size=1920,1080 \
    --password-store=basic \
    "http://localhost/opensis/" > /dev/null 2>&1 &

# Wait for window
for i in {1..30}; do
    if wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        break
    fi
    sleep 1
done

# Maximize
wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Capture Initial State
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="