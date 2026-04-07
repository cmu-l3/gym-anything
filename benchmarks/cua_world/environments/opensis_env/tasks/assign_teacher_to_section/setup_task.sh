#!/bin/bash
set -euo pipefail

echo "=== Setting up assign_teacher_to_section task ==="

# 1. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Services Running
echo "Ensuring LAMP stack is active..."
service mariadb start || true
service apache2 start || true
sleep 2

# 3. DB Setup: Create required data
# We need:
# - A School Period (Period 2)
# - A Course (Chemistry 101)
# - A Teacher (Patricia Hernandez)
# - A Course Period (Section) linking Course+Period with NO Teacher

echo "Seeding database..."
mysql -u opensis_user -p'opensis_password_123' opensis <<EOF
-- Ensure Period 2 exists
INSERT INTO school_periods (period_id, school_id, syear, title, short_name, sort_order, length, start_time, end_time)
VALUES (2, 1, 2025, 'Period 2', '2', 2, 60, '09:00:00', '10:00:00')
ON DUPLICATE KEY UPDATE title='Period 2';

-- Ensure Teacher Patricia Hernandez exists
INSERT INTO staff (staff_id, current_school_id, title, first_name, last_name, gender, email, profile, profile_id)
VALUES (99, 1, 'Ms.', 'Patricia', 'Hernandez', 'Female', 'phernandez@school.edu', 'teacher', 2)
ON DUPLICATE KEY UPDATE first_name='Patricia', last_name='Hernandez', profile='teacher';

-- Link Staff to School (Critical for them to appear in dropdowns)
INSERT INTO staff_school_relationship (staff_id, school_id, syear, start_date)
VALUES (99, 1, 2025, '2024-08-01')
ON DUPLICATE KEY UPDATE syear=2025;

-- Ensure Course Chemistry 101 exists
INSERT INTO courses (course_id, course_name, course_code, subject_area, grade_level, credits)
VALUES (101, 'Chemistry 101', 'CHEM101', 'Science', '10', 1.0)
ON DUPLICATE KEY UPDATE course_name='Chemistry 101';

-- Ensure Course Section exists for Period 2 with NULL teacher
-- We use DELETE/INSERT to ensure clean state (NULL teacher)
DELETE FROM course_periods WHERE course_id=101 AND period_id=2;

INSERT INTO course_periods (course_period_id, course_id, period_id, syear, school_id, teacher_id, room, total_seats)
VALUES (202, 101, 2, 2025, 1, NULL, 'Lab 1', 30);
EOF

# 4. Record Initial State
# Verify teacher is NULL
INITIAL_TEACHER=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e "SELECT IFNULL(teacher_id, 'NULL') FROM course_periods WHERE course_period_id=202")
echo "Initial teacher_id: $INITIAL_TEACHER"
echo "$INITIAL_TEACHER" > /tmp/initial_teacher_id.txt

# 5. Browser Setup
echo "Launching browser..."
pkill -f chrome 2>/dev/null || true

# Determine Chrome binary
if command -v google-chrome-stable &> /dev/null; then
    CHROME="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME="chromium-browser"
else
    CHROME="chrome"
fi

# Launch
su - ga -c "DISPLAY=:1 $CHROME \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --window-size=1920,1080 \
    --password-store=basic \
    http://localhost/opensis/ &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Chrome\|Chromium"; then
        echo "Browser window found."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="