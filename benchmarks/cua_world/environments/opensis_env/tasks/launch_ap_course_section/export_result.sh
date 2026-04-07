#!/bin/bash
set -euo pipefail

echo "=== Exporting launch_ap_course_section task result ==="

export DISPLAY=${DISPLAY:-:1}

# DB credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"
MYSQL_CMD="mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -B -e"

# 1. Capture final screenshot
scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get baseline values
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_STAFF=$(cat /tmp/initial_staff_count 2>/dev/null || echo "0")
INITIAL_COURSE=$(cat /tmp/initial_course_count 2>/dev/null || echo "0")

# 3. Query database for all verification targets

# Staff: Dr. Cruz (staff table columns: staff_id, first_name, last_name, email, profile)
STAFF_DATA=$($MYSQL_CMD "SELECT staff_id, first_name, last_name, email, profile FROM staff WHERE first_name='Nathan' AND last_name='Cruz' LIMIT 1" 2>/dev/null || echo "")

# Course: APES101 (courses table columns: course_id, title, short_name, subject_id, grade_level)
COURSE_DATA=$($MYSQL_CMD "SELECT course_id, title, short_name, subject_id, grade_level FROM courses WHERE short_name='APES101' LIMIT 1" 2>/dev/null || echo "")

# Course section (course_periods: course_period_id, title, teacher_id, total_seats, credits)
SECTION_DATA=$($MYSQL_CMD "
    SELECT cp.course_period_id, cp.title, cp.total_seats, cp.teacher_id, cp.credits,
           IFNULL(s.first_name,'') as teacher_first, IFNULL(s.last_name,'') as teacher_last
    FROM course_periods cp
    LEFT JOIN staff s ON cp.teacher_id = s.staff_id
    INNER JOIN courses c ON cp.course_id = c.course_id
    WHERE c.short_name = 'APES101'
    LIMIT 1
" 2>/dev/null || echo "")

# Enrollment: students scheduled in APES101 section
ENROLLMENT_DATA=$($MYSQL_CMD "
    SELECT st.first_name, st.last_name, sch.student_id
    FROM schedule sch
    INNER JOIN course_periods cp ON sch.course_period_id = cp.course_period_id
    INNER JOIN courses c ON cp.course_id = c.course_id
    INNER JOIN students st ON sch.student_id = st.student_id
    WHERE c.short_name = 'APES101'
    ORDER BY st.last_name
" 2>/dev/null || echo "")

# Gradebook category (gradebook_assignment_types: assignment_type_id, title, final_grade_percent)
CATEGORY_DATA=$($MYSQL_CMD "
    SELECT gat.assignment_type_id, gat.title, gat.final_grade_percent
    FROM gradebook_assignment_types gat
    INNER JOIN course_periods cp ON gat.course_period_id = cp.course_period_id
    INNER JOIN courses c ON cp.course_id = c.course_id
    WHERE c.short_name = 'APES101' AND gat.title = 'Assessments'
    LIMIT 1
" 2>/dev/null || echo "")

# Gradebook assignment (gradebook_assignments: assignment_id, title, points, assignment_type_id)
ASSIGNMENT_DATA=$($MYSQL_CMD "
    SELECT ga.assignment_id, ga.title, ga.points, ga.assignment_type_id
    FROM gradebook_assignments ga
    INNER JOIN course_periods cp ON ga.course_period_id = cp.course_period_id
    INNER JOIN courses c ON cp.course_id = c.course_id
    WHERE c.short_name = 'APES101' AND ga.title = 'Baseline Assessment'
    LIMIT 1
" 2>/dev/null || echo "")

# Grades from gradebook_grades (student_id, assignment_id, points)
GRADE_DATA=$($MYSQL_CMD "
    SELECT st.first_name, st.last_name, gg.points
    FROM gradebook_grades gg
    INNER JOIN students st ON gg.student_id = st.student_id
    INNER JOIN course_periods cp ON gg.course_period_id = cp.course_period_id
    INNER JOIN courses c ON cp.course_id = c.course_id
    WHERE c.short_name = 'APES101'
    ORDER BY st.last_name
" 2>/dev/null || echo "")

# Attendance from attendance_period for 2025-01-13
ATTENDANCE_DATA=$($MYSQL_CMD "
    SELECT st.first_name, st.last_name, ap.attendance_code
    FROM attendance_period ap
    INNER JOIN students st ON ap.student_id = st.student_id
    WHERE ap.school_date = '2025-01-13'
      AND st.student_id IN (
        SELECT student_id FROM students
        WHERE (first_name='Olivia' AND last_name='Martinez')
           OR (first_name='Ethan'  AND last_name='Park')
           OR (first_name='Sophia' AND last_name='Williams')
      )
    ORDER BY st.last_name
" 2>/dev/null || echo "")

# Fallback: attendance_day for 2025-01-13 (state_value: 1.0=present, 0.0=absent)
ATTENDANCE_DAY_DATA=$($MYSQL_CMD "
    SELECT st.first_name, st.last_name, ad.state_value
    FROM attendance_day ad
    INNER JOIN students st ON ad.student_id = st.student_id
    WHERE ad.school_date = '2025-01-13'
      AND st.student_id IN (
        SELECT student_id FROM students
        WHERE (first_name='Olivia' AND last_name='Martinez')
           OR (first_name='Ethan'  AND last_name='Park')
           OR (first_name='Sophia' AND last_name='Williams')
      )
    ORDER BY st.last_name
" 2>/dev/null || echo "")

# Check browser running
APP_RUNNING="false"
if pgrep -f "chrome|chromium" > /dev/null; then
    APP_RUNNING="true"
fi

# 4. Construct JSON result via Python (safe escaping)
python3 -c "
import json

result = {
    'task_start': int('$TASK_START' or '0'),
    'initial_staff_count': int('$INITIAL_STAFF' or '0'),
    'initial_course_count': int('$INITIAL_COURSE' or '0'),
    'staff_data': '''$STAFF_DATA'''.strip(),
    'course_data': '''$COURSE_DATA'''.strip(),
    'section_data': '''$SECTION_DATA'''.strip(),
    'enrollment_data': '''$ENROLLMENT_DATA'''.strip(),
    'category_data': '''$CATEGORY_DATA'''.strip(),
    'assignment_data': '''$ASSIGNMENT_DATA'''.strip(),
    'grade_data': '''$GRADE_DATA'''.strip(),
    'attendance_data': '''$ATTENDANCE_DATA'''.strip(),
    'attendance_day_data': '''$ATTENDANCE_DAY_DATA'''.strip(),
    'app_running': '$APP_RUNNING' == 'true',
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

chmod 666 /tmp/task_result.json
echo "Exported result to /tmp/task_result.json"
cat /tmp/task_result.json
