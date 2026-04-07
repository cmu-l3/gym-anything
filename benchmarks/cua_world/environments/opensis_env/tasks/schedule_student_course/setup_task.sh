#!/bin/bash
set -e

echo "=== Setting up schedule_student_course task ==="

# 1. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Services are Running
echo "Checking services..."
service mariadb start || true
service apache2 start || true

# Wait for DB
for i in {1..30}; do
    if mysql -u root -e "SELECT 1" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# 3. Prepare Database Data
# We need: Student (Maria Garcia), Course (AP Biology), Course Period (Section)
# OpenSIS schema requires linking these correctly.

echo "Preparing database data..."
mysql -u opensis_user -popensis_password_123 opensis <<EOF
-- 1. Ensure School Year exists (using logic from direct_db_setup.sh for current year)
-- We assume the default installation setup (id=1 is the school)

-- 2. Create Student: Maria Garcia
INSERT INTO students (student_id, first_name, last_name, gender, birthdate, grade_level)
SELECT 9001, 'Maria', 'Garcia', 'Female', '2008-05-14', '10'
WHERE NOT EXISTS (SELECT 1 FROM students WHERE first_name='Maria' AND last_name='Garcia');

-- Ensure Student Enrollment (Current Year)
-- Get current syear from schools table
SET @syear = (SELECT syear FROM schools WHERE id=1 LIMIT 1);
INSERT INTO student_enrollment (student_id, school_id, grade_id, syear, start_date, enrollment_code)
SELECT 9001, 1, 2, @syear, CURDATE(), 'New'
WHERE NOT EXISTS (SELECT 1 FROM student_enrollment WHERE student_id=9001 AND syear=@syear);

-- 3. Create Course: AP Biology (BIO-201)
INSERT INTO courses (course_id, syear, school_id, title, short_name, grade_level, credits)
SELECT 8001, @syear, 1, 'AP Biology', 'BIO-201', '10', 1.0
WHERE NOT EXISTS (SELECT 1 FROM courses WHERE short_name='BIO-201');

-- 4. Create Course Period (Section)
-- Needs linking to a marking period (id=1 usually FY) and a teacher (id=1 admin)
INSERT INTO course_periods (course_period_id, syear, school_id, course_id, title, short_name, marking_period_id, mp, period_id, teacher_id, total_seats, filled_seats)
SELECT 7001, @syear, 1, 8001, 'AP Biology - Sec 1', 'BIO-201-01', 1, 'FY', 1, 1, 30, 0
WHERE NOT EXISTS (SELECT 1 FROM course_periods WHERE short_name='BIO-201-01');

-- 5. Clean up any existing schedule for this student to ensure clean state
DELETE FROM schedule WHERE student_id = 9001 AND course_period_id = 7001;
EOF

# 4. Record Initial State
# Count schedule records for Maria
INITIAL_COUNT=$(mysql -u opensis_user -popensis_password_123 opensis -N -e "SELECT COUNT(*) FROM schedule WHERE student_id=9001" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_schedule_count.txt
echo "Initial schedule count for Maria: $INITIAL_COUNT"

# 5. Browser Setup
echo "Launching Browser..."
pkill -f chrome || true

# Start Chrome on Login Page
su - ga -c "DISPLAY=:1 google-chrome-stable --start-maximized --no-sandbox --disable-infobars http://localhost/opensis/ &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Chrome"; then
        echo "Chrome window found"
        break
    fi
    sleep 1
done

# Ensure Maximize and Focus
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# 6. Capture Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="