#!/bin/bash
set -e

echo "=== Setting up cancel_course_enrollments task ==="

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Services are running
service mariadb start || true
service apache2 start || true

# Wait for DB
for i in {1..30}; do
    if mysql -u root -e "SELECT 1" &>/dev/null; then
        break
    fi
    sleep 1
done

# 3. Data Setup using SQL
# We need:
# - A School Year (usually set up by install, we assume ID 1 or current)
# - Two Courses: ART-303 (Target) and MATH-101 (Control)
# - A Course Period (Section) for each
# - 5 Students
# - Schedule records linking students to both courses

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# SQL Setup Script
cat > /tmp/setup_data.sql <<EOF
USE $DB_NAME;

-- Ensure School Year exists (assuming standard install has school_id=1, syear=2025)
-- We will fetch the current syear to be safe
SET @SYEAR = (SELECT syear FROM schools WHERE id=1 LIMIT 1);
SET @MP_ID = (SELECT marking_period_id FROM school_years WHERE school_id=1 LIMIT 1);

-- 1. Create Courses
INSERT INTO courses (course_name, course_code, subject_area, grade_level, credits)
SELECT 'Advanced Pottery', 'ART-303', 'Arts', '12', '1.0'
WHERE NOT EXISTS (SELECT 1 FROM courses WHERE course_code = 'ART-303');

INSERT INTO courses (course_name, course_code, subject_area, grade_level, credits)
SELECT 'Calculus I', 'MATH-101', 'Math', '12', '1.0'
WHERE NOT EXISTS (SELECT 1 FROM courses WHERE course_code = 'MATH-101');

SET @ART_ID = (SELECT course_id FROM courses WHERE course_code = 'ART-303');
SET @MATH_ID = (SELECT course_id FROM courses WHERE course_code = 'MATH-101');

-- 2. Create Course Periods (Sections)
-- Only insert if not exists. We assume period_id 1 exists or just use arbitrary.
INSERT INTO course_periods (course_id, short_name, title, mp, marking_period_id)
SELECT @ART_ID, '1', 'Advanced Pottery - Sec 1', 'FY', @MP_ID
WHERE NOT EXISTS (SELECT 1 FROM course_periods WHERE course_id = @ART_ID);

INSERT INTO course_periods (course_id, short_name, title, mp, marking_period_id)
SELECT @MATH_ID, '1', 'Calculus I - Sec 1', 'FY', @MP_ID
WHERE NOT EXISTS (SELECT 1 FROM course_periods WHERE course_id = @MATH_ID);

SET @ART_CP_ID = (SELECT course_period_id FROM course_periods WHERE course_id = @ART_ID LIMIT 1);
SET @MATH_CP_ID = (SELECT course_period_id FROM course_periods WHERE course_id = @MATH_ID LIMIT 1);

-- 3. Create Students and Enrollments
-- We'll create 5 students
DELIMITER //
CREATE PROCEDURE SetupStudents()
BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE new_student_id INT;
    WHILE i <= 5 DO
        -- Insert Student if not exists
        IF NOT EXISTS (SELECT 1 FROM students WHERE first_name = CONCAT('PotteryUser', i)) THEN
            INSERT INTO students (first_name, last_name, username, password, grade_level, is_active)
            VALUES (CONCAT('PotteryUser', i), 'Test', CONCAT('puser', i), 'password', '12', 'Y');
            
            SET new_student_id = LAST_INSERT_ID();
            
            -- Enroll in School
            INSERT INTO student_enrollment (student_id, school_id, syear, grade_id, start_date, end_date)
            VALUES (new_student_id, 1, @SYEAR, 4, '2024-09-01', NULL); -- Grade 12 is usually id 4 in demo
            
            -- Schedule in ART-303
            INSERT INTO schedule (student_id, course_id, course_period_id, marking_period_id, scheduler_lock)
            VALUES (new_student_id, @ART_ID, @ART_CP_ID, @MP_ID, 'Y');
            
            -- Schedule in MATH-101 (Control)
            INSERT INTO schedule (student_id, course_id, course_period_id, marking_period_id, scheduler_lock)
            VALUES (new_student_id, @MATH_ID, @MATH_CP_ID, @MP_ID, 'Y');
        ELSE
            -- If student exists, ensure they are enrolled in ART-303 (in case of re-run)
            SET new_student_id = (SELECT student_id FROM students WHERE first_name = CONCAT('PotteryUser', i) LIMIT 1);
            
            INSERT IGNORE INTO schedule (student_id, course_id, course_period_id, marking_period_id, scheduler_lock)
            VALUES (new_student_id, @ART_ID, @ART_CP_ID, @MP_ID, 'Y');
            
             INSERT IGNORE INTO schedule (student_id, course_id, course_period_id, marking_period_id, scheduler_lock)
            VALUES (new_student_id, @MATH_ID, @MATH_CP_ID, @MP_ID, 'Y');
        END IF;
        
        SET i = i + 1;
    END WHILE;
END //
DELIMITER ;

CALL SetupStudents();
DROP PROCEDURE SetupStudents;
EOF

# Execute SQL
mysql -u "$DB_USER" -p"$DB_PASS" < /tmp/setup_data.sql

# 4. Prepare Browser
# Kill existing
pkill -f chrome 2>/dev/null || true

# Start Chrome
echo "Starting Chrome..."
su - ga -c "google-chrome-stable --no-sandbox --start-maximized --disable-gpu http://localhost/opensis/ &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Chrome"; then
        break
    fi
    sleep 1
done

# Focus and Maximize
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 5. Record Initial State for Debugging
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT count(*) FROM schedule WHERE course_period_id IN (SELECT course_period_id FROM course_periods WHERE course_id = (SELECT course_id FROM courses WHERE course_code='ART-303'))" > /tmp/initial_enrollment_count.txt

echo "=== Setup complete ==="