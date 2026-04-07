#!/bin/bash
set -e
echo "=== Setting up task: batch_generate_schedules ==="

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Database and Web Server are running
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Wait for DB
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# 3. Clean up previous artifacts
rm -rf /home/ga/Downloads/*
mkdir -p /home/ga/Downloads
chown ga:ga /home/ga/Downloads

# 4. Inject Real Data (Students and Schedules)
# We need specific students to verify filtering logic (Inclusion vs Exclusion)
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
-- Ensure Grade Levels exist
INSERT INTO school_gradelevels (id, school_id, short_name, title, sort_order) VALUES
(9, 1, '09', 'Grade 9', 1),
(10, 1, '10', 'Grade 10', 2)
ON DUPLICATE KEY UPDATE title=VALUES(title);

-- Create Course 'Homeroom'
INSERT INTO courses (course_id, course_title, course_code, school_id, credit_hours, syear) 
VALUES (1001, 'Homeroom', 'HR-001', 1, 0, 2025)
ON DUPLICATE KEY UPDATE course_title='Homeroom';

-- Create Course Period (Section)
INSERT INTO course_periods (course_period_id, course_id, title, short_name, mp, syear, school_id, teacher_id)
VALUES (1001, 1001, 'Homeroom Section', 'HR-A', 'FY', 2025, 1, 1)
ON DUPLICATE KEY UPDATE title='Homeroom Section';

-- Create Target Students (Grade 9)
INSERT INTO students (student_id, first_name, last_name, grade_level_id, school_id, is_active, username) VALUES
(2001, 'Freshman', 'One', 9, 1, 'Y', 'fresh1'),
(2002, 'Freshman', 'Two', 9, 1, 'Y', 'fresh2'),
(2003, 'Freshman', 'Three', 9, 1, 'Y', 'fresh3')
ON DUPLICATE KEY UPDATE grade_level_id=9;

-- Create Distractor Student (Grade 10)
INSERT INTO students (student_id, first_name, last_name, grade_level_id, school_id, is_active, username) VALUES
(3001, 'Senior', 'Student', 10, 1, 'Y', 'senior1')
ON DUPLICATE KEY UPDATE grade_level_id=10;

-- Enroll Students
INSERT INTO student_enrollment (student_id, school_id, syear, grade_level_id, start_date, enrollment_code) VALUES
(2001, 1, 2025, 9, '2024-09-01', 1),
(2002, 1, 2025, 9, '2024-09-01', 1),
(2003, 1, 2025, 9, '2024-09-01', 1),
(3001, 1, 2025, 10, '2024-09-01', 1)
ON DUPLICATE KEY UPDATE syear=2025;

-- Schedule Students into Homeroom
INSERT INTO schedule (student_id, school_id, syear, course_id, course_period_id, mp) VALUES
(2001, 1, 2025, 1001, 1001, 'FY'),
(2002, 1, 2025, 1001, 1001, 'FY'),
(2003, 1, 2025, 1001, 1001, 'FY'),
(3001, 1, 2025, 1001, 1001, 'FY')
ON DUPLICATE KEY UPDATE course_period_id=1001;
EOF

# 5. Launch Chrome to Login Page
if ! pgrep -f "chrome" > /dev/null; then
    su - ga -c "google-chrome-stable --no-sandbox --start-maximized http://localhost/opensis/ &"
    sleep 5
fi

# 6. Ensure Window is Maximize
for i in {1..10}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "Chrome" | head -n1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID"
        DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz
        break
    fi
    sleep 1
done

# 7. Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="