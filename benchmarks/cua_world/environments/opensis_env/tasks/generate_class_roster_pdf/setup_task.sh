#!/bin/bash
set -e
echo "=== Setting up Generate Class Roster Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Start Services
echo "Starting services..."
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Wait for database
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "Database is up."
        break
    fi
    sleep 1
done

# 3. Clean up previous artifacts
rm -f /home/ga/Documents/algebra_roster.pdf
mkdir -p /home/ga/Documents

# 4. Populate Database with Specific Scenario Data
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Use MySQL to inject data:
# - Ensure School exists
# - Create Course 'Algebra I'
# - Create Students 'John Smith' and 'Jane Doe'
# - Enroll them in the course
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
-- Ensure School
UPDATE schools SET title='Demo School' WHERE id=1;

-- Create Students
INSERT INTO students (student_id, first_name, last_name, gender, birthdate, grade_level, username, password) VALUES 
(1001, 'John', 'Smith', 'Male', '2008-01-15', '9', 'jsmith', 'password'),
(1002, 'Jane', 'Doe', 'Female', '2008-05-20', '9', 'jdoe', 'password')
ON DUPLICATE KEY UPDATE first_name=VALUES(first_name), last_name=VALUES(last_name);

-- Create Course 'Algebra I'
INSERT INTO courses (course_id, course_title, course_short_name, credit_hours, school_id, grade_level) VALUES 
(501, 'Algebra I', 'ALG1', 1.0, 1, '9')
ON DUPLICATE KEY UPDATE course_title=VALUES(course_title);

-- Create Course Period/Section
-- Note: schema structure for OpenSIS might vary, inserting into core tables
INSERT INTO course_periods (course_period_id, course_id, title, short_name, mp, marking_period_id, school_id) VALUES 
(50101, 501, 'Section 1', '1', 'FY', 1, 1)
ON DUPLICATE KEY UPDATE title=VALUES(title);

-- Enroll Students
INSERT INTO schedule (student_id, course_period_id, course_id, marking_period_id, school_id) VALUES 
(1001, 50101, 501, 1, 1),
(1002, 50101, 501, 1, 1)
ON DUPLICATE KEY UPDATE course_id=VALUES(course_id);

-- Link staff (admin) to school to ensure visibility
INSERT INTO staff_school_relationship (staff_id, school_id, syear) VALUES
(1, 1, 2025)
ON DUPLICATE KEY UPDATE syear=2025;
EOF

echo "Database populated."

# 5. Launch Chrome to the login page (setup state)
if ! pgrep -f "chrome" > /dev/null; then
    echo "Starting Chrome..."
    su - ga -c "DISPLAY=:1 google-chrome-stable --start-maximized http://localhost/opensis/ &"
    sleep 5
fi

# 6. Ensure window is focused and maximized
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# 7. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="