#!/bin/bash
set -e
echo "=== Setting up Mass Record Attendance Task ==="

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt
date -I > /tmp/task_date.txt

# 2. Ensure Database Services are running
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true
sleep 3

# 3. Setup Database State
# We need to ensure:
# - 'Excused' attendance code exists
# - Sufficient Grade 12 students exist (Target)
# - Sufficient Grade 9 students exist (Control)
# - No attendance exists for today (clean slate)

echo "Configuring database..."
mysql -u opensis_user -p'opensis_password_123' opensis <<EOF
-- 1. Create Excused Code
INSERT INTO attendance_codes (title, short_name, type, state_code, sort_order) 
VALUES ('Excused', 'E', 'Absent', 'E', 5) 
ON DUPLICATE KEY UPDATE title='Excused', short_name='E';

-- 2. Create Target Students (Grade 12)
INSERT INTO students (first_name, last_name, username, password, grade_level, school_id, is_active, enrollment_start_date)
SELECT 'Senior', 'One', 'sen1', 'pass', '12', 1, 'Y', CURDATE()
WHERE NOT EXISTS (SELECT 1 FROM students WHERE username='sen1');

INSERT INTO students (first_name, last_name, username, password, grade_level, school_id, is_active, enrollment_start_date)
SELECT 'Senior', 'Two', 'sen2', 'pass', '12', 1, 'Y', CURDATE()
WHERE NOT EXISTS (SELECT 1 FROM students WHERE username='sen2');

INSERT INTO students (first_name, last_name, username, password, grade_level, school_id, is_active, enrollment_start_date)
SELECT 'Senior', 'Three', 'sen3', 'pass', '12', 1, 'Y', CURDATE()
WHERE NOT EXISTS (SELECT 1 FROM students WHERE username='sen3');

-- 3. Create Control Students (Grade 9)
INSERT INTO students (first_name, last_name, username, password, grade_level, school_id, is_active, enrollment_start_date)
SELECT 'Freshman', 'Control', 'fresh1', 'pass', '9', 1, 'Y', CURDATE()
WHERE NOT EXISTS (SELECT 1 FROM students WHERE username='fresh1');

INSERT INTO students (first_name, last_name, username, password, grade_level, school_id, is_active, enrollment_start_date)
SELECT 'Freshman', 'ControlTwo', 'fresh2', 'pass', '9', 1, 'Y', CURDATE()
WHERE NOT EXISTS (SELECT 1 FROM students WHERE username='fresh2');

-- 4. Ensure Student Enrollment exists (link to school)
INSERT IGNORE INTO student_enrollment (student_id, school_id, syear, grade_id, start_date, end_date, enrollment_code)
SELECT student_id, 1, 2025, (SELECT id FROM school_gradelevels WHERE short_name=students.grade_level LIMIT 1), CURDATE(), NULL, 1
FROM students WHERE username IN ('sen1', 'sen2', 'sen3', 'fresh1', 'fresh2');

-- 5. Clear attendance for today to ensure clean slate
DELETE FROM attendance_period WHERE school_date = CURDATE();
DELETE FROM attendance_day WHERE school_date = CURDATE();
EOF

# 4. Launch Browser and Login
echo "Launching OpenSIS..."
# Kill any existing instances
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true

# Determine browser command
if command -v google-chrome-stable &> /dev/null; then
    BROWSER="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    BROWSER="chromium-browser"
else
    BROWSER="chrome-browser"
fi

# Launch browser
su - ga -c "DISPLAY=:1 $BROWSER --no-first-run --no-default-browser-check --start-maximized http://localhost/opensis/ &"

# Wait for browser window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Chrome\|Chromium"; then
        echo "Browser started."
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Take Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="