#!/bin/bash
set -euo pipefail

echo "=== Setting up launch_ap_course_section task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

xhost +local: 2>/dev/null || true

# ── 1. Ensure services are running ──────────────────────────────────────────
echo "Checking services..."
systemctl is-active --quiet mariadb || systemctl start mariadb
systemctl is-active --quiet apache2 || systemctl start apache2
sleep 2

# Wait for DB to be ready
for i in {1..15}; do
    if mysqladmin ping -u opensis_user -p'opensis_password_123' --silent 2>/dev/null; then
        echo "Database ready."
        break
    fi
    sleep 1
done

# ── 2. Clean any pre-existing target data (idempotent) ──────────────────────
echo "Cleaning stale target data..."
mysql -u opensis_user -p'opensis_password_123' opensis 2>/dev/null <<'CLEAN_SQL' || true
SET @syear = (SELECT syear FROM schools WHERE id = 1 LIMIT 1);

-- Clean gradebook grades for target course
DELETE gg FROM gradebook_grades gg
  INNER JOIN course_periods cp ON gg.course_period_id = cp.course_period_id
  INNER JOIN courses c         ON cp.course_id = c.course_id
  WHERE c.short_name = 'APES101';

-- Clean report card grades for target course (in case any were posted)
DELETE rcg FROM student_report_card_grades rcg
  INNER JOIN course_periods cp ON rcg.course_period_id = cp.course_period_id
  INNER JOIN courses c         ON cp.course_id = c.course_id
  WHERE c.short_name = 'APES101';

-- Clean gradebook assignments for target course
DELETE ga FROM gradebook_assignments ga
  INNER JOIN course_periods cp ON ga.course_period_id = cp.course_period_id
  INNER JOIN courses c         ON cp.course_id = c.course_id
  WHERE c.short_name = 'APES101';

-- Clean gradebook assignment types (categories) for target course
DELETE gat FROM gradebook_assignment_types gat
  INNER JOIN course_periods cp ON gat.course_period_id = cp.course_period_id
  INNER JOIN courses c         ON cp.course_id = c.course_id
  WHERE c.short_name = 'APES101';

-- Clean attendance_period for target students in target course
DELETE ap FROM attendance_period ap
  INNER JOIN schedule sch      ON ap.student_id = sch.student_id
  INNER JOIN course_periods cp ON sch.course_period_id = cp.course_period_id
  INNER JOIN courses c         ON cp.course_id = c.course_id
  WHERE c.short_name = 'APES101';

-- Clean schedule (enrollments) for target course
DELETE sch FROM schedule sch
  INNER JOIN course_periods cp ON sch.course_period_id = cp.course_period_id
  INNER JOIN courses c         ON cp.course_id = c.course_id
  WHERE c.short_name = 'APES101';

-- Clean course periods (sections)
DELETE cp FROM course_periods cp
  INNER JOIN courses c ON cp.course_id = c.course_id
  WHERE c.short_name = 'APES101';

-- Clean the course itself
DELETE FROM courses WHERE short_name = 'APES101';

-- Clean Dr. Cruz staff records
DELETE FROM staff_school_relationship
  WHERE staff_id IN (SELECT staff_id FROM staff WHERE first_name='Nathan' AND last_name='Cruz');
DELETE FROM staff_school_info
  WHERE staff_id IN (SELECT staff_id FROM staff WHERE first_name='Nathan' AND last_name='Cruz');
DELETE FROM login_authentication
  WHERE user_id IN (SELECT staff_id FROM staff WHERE first_name='Nathan' AND last_name='Cruz');
DELETE FROM staff WHERE first_name='Nathan' AND last_name='Cruz';

-- Clean any leftover attendance records for our students on 2025-01-13
DELETE FROM attendance_period
  WHERE school_date = '2025-01-13'
    AND student_id IN (
      SELECT student_id FROM students
      WHERE (first_name='Olivia' AND last_name='Martinez')
         OR (first_name='Ethan'  AND last_name='Park')
         OR (first_name='Sophia' AND last_name='Williams')
    );
DELETE FROM attendance_day
  WHERE school_date = '2025-01-13'
    AND student_id IN (
      SELECT student_id FROM students
      WHERE (first_name='Olivia' AND last_name='Martinez')
         OR (first_name='Ethan'  AND last_name='Park')
         OR (first_name='Sophia' AND last_name='Williams')
    );
CLEAN_SQL
echo "Stale data cleaned."

# ── 3. Ensure prerequisite data exists ──────────────────────────────────────
echo "Seeding prerequisite data (students, subject, period)..."
mysql -u opensis_user -p'opensis_password_123' opensis 2>/dev/null <<'SEED_SQL' || true
SET @syear = (SELECT syear FROM schools WHERE id = 1 LIMIT 1);
SET @grade11_id = (SELECT id FROM school_gradelevels WHERE short_name='11' AND school_id=1 LIMIT 1);

-- Ensure Science subject exists
INSERT INTO course_subjects (school_id, syear, title, short_name)
  SELECT 1, @syear, 'Science', 'SCI' FROM DUAL
  WHERE NOT EXISTS (SELECT 1 FROM course_subjects WHERE title='Science' AND school_id=1 AND syear=@syear);

-- Ensure Period 3 exists in school_periods
INSERT INTO school_periods (school_id, syear, sort_order, title, short_name, length)
  SELECT 1, @syear, 3, 'Period 3', '3', 50 FROM DUAL
  WHERE NOT EXISTS (SELECT 1 FROM school_periods WHERE title='Period 3' AND school_id=1 AND syear=@syear);

-- Ensure attendance code category exists
INSERT INTO attendance_code_categories (syear, school_id, title)
  SELECT @syear, 1, 'Attendance Codes' FROM DUAL
  WHERE NOT EXISTS (SELECT 1 FROM attendance_code_categories WHERE school_id=1 AND syear=@syear);

-- Ensure attendance codes exist (P=Present, A=Absent, T=Tardy, H=Half Day)
INSERT INTO attendance_codes (syear, school_id, title, short_name, type, state_code, default_code, table_name, sort_order)
  SELECT @syear, 1, 'Present', 'P', 'teacher', 'H', 'Y',
    (SELECT id FROM attendance_code_categories WHERE school_id=1 AND syear=@syear LIMIT 1), 1 FROM DUAL
  WHERE NOT EXISTS (SELECT 1 FROM attendance_codes WHERE short_name='P' AND school_id=1 AND syear=@syear);
INSERT INTO attendance_codes (syear, school_id, title, short_name, type, state_code, default_code, table_name, sort_order)
  SELECT @syear, 1, 'Absent', 'A', 'teacher', 'A', 'N',
    (SELECT id FROM attendance_code_categories WHERE school_id=1 AND syear=@syear LIMIT 1), 2 FROM DUAL
  WHERE NOT EXISTS (SELECT 1 FROM attendance_codes WHERE short_name='A' AND school_id=1 AND syear=@syear);
INSERT INTO attendance_codes (syear, school_id, title, short_name, type, state_code, default_code, table_name, sort_order)
  SELECT @syear, 1, 'Tardy', 'T', 'teacher', 'H', 'N',
    (SELECT id FROM attendance_code_categories WHERE school_id=1 AND syear=@syear LIMIT 1), 3 FROM DUAL
  WHERE NOT EXISTS (SELECT 1 FROM attendance_codes WHERE short_name='T' AND school_id=1 AND syear=@syear);
INSERT INTO attendance_codes (syear, school_id, title, short_name, type, state_code, default_code, table_name, sort_order)
  SELECT @syear, 1, 'Half Day', 'H', 'teacher', 'H', 'N',
    (SELECT id FROM attendance_code_categories WHERE school_id=1 AND syear=@syear LIMIT 1), 4 FROM DUAL
  WHERE NOT EXISTS (SELECT 1 FROM attendance_codes WHERE short_name='H' AND school_id=1 AND syear=@syear);

-- ── Student: Olivia Martinez ──
-- Clean first (idempotent)
DELETE FROM attendance_period WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Olivia' AND last_name='Martinez');
DELETE FROM attendance_day WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Olivia' AND last_name='Martinez');
DELETE FROM gradebook_grades WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Olivia' AND last_name='Martinez');
DELETE FROM schedule WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Olivia' AND last_name='Martinez');
DELETE FROM student_enrollment WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Olivia' AND last_name='Martinez');
DELETE FROM students WHERE first_name='Olivia' AND last_name='Martinez';

SET @start_dt = DATE(CONCAT(CAST(@syear - 1 AS UNSIGNED), '-08-15'));

INSERT INTO students (first_name, last_name, birthdate, gender)
VALUES ('Olivia', 'Martinez', '2007-03-14', 'Female');
SET @oliv_id = LAST_INSERT_ID();

INSERT INTO student_enrollment (student_id, school_id, syear, grade_id, start_date)
VALUES (@oliv_id, 1, @syear, @grade11_id, @start_dt);

-- ── Student: Ethan Park ──
DELETE FROM attendance_period WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Ethan' AND last_name='Park');
DELETE FROM attendance_day WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Ethan' AND last_name='Park');
DELETE FROM gradebook_grades WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Ethan' AND last_name='Park');
DELETE FROM schedule WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Ethan' AND last_name='Park');
DELETE FROM student_enrollment WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Ethan' AND last_name='Park');
DELETE FROM students WHERE first_name='Ethan' AND last_name='Park';

INSERT INTO students (first_name, last_name, birthdate, gender)
VALUES ('Ethan', 'Park', '2007-07-22', 'Male');
SET @ethan_id = LAST_INSERT_ID();

INSERT INTO student_enrollment (student_id, school_id, syear, grade_id, start_date)
VALUES (@ethan_id, 1, @syear, @grade11_id, @start_dt);

-- ── Student: Sophia Williams ──
DELETE FROM attendance_period WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Sophia' AND last_name='Williams');
DELETE FROM attendance_day WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Sophia' AND last_name='Williams');
DELETE FROM gradebook_grades WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Sophia' AND last_name='Williams');
DELETE FROM schedule WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Sophia' AND last_name='Williams');
DELETE FROM student_enrollment WHERE student_id IN (SELECT student_id FROM students WHERE first_name='Sophia' AND last_name='Williams');
DELETE FROM students WHERE first_name='Sophia' AND last_name='Williams';

INSERT INTO students (first_name, last_name, birthdate, gender)
VALUES ('Sophia', 'Williams', '2007-11-05', 'Female');
SET @sophia_id = LAST_INSERT_ID();

INSERT INTO student_enrollment (student_id, school_id, syear, grade_id, start_date)
VALUES (@sophia_id, 1, @syear, @grade11_id, @start_dt);
SEED_SQL
echo "Students seeded."

# ── 4. Record baseline state for anti-gaming ────────────────────────────────
date +%s > /tmp/task_start_timestamp

mysql -u opensis_user -p'opensis_password_123' opensis \
  -N -e "SELECT COUNT(*) FROM staff" 2>/dev/null | tail -1 > /tmp/initial_staff_count || echo "0" > /tmp/initial_staff_count
mysql -u opensis_user -p'opensis_password_123' opensis \
  -N -e "SELECT COUNT(*) FROM courses WHERE short_name='APES101'" 2>/dev/null | tail -1 > /tmp/initial_course_count || echo "0" > /tmp/initial_course_count

echo "Baseline: $(cat /tmp/initial_staff_count) staff, $(cat /tmp/initial_course_count) APES101 courses"

# ── 5. Launch browser ───────────────────────────────────────────────────────
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true
sleep 1

if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
elif command -v chrome-browser &> /dev/null; then
    CHROME_CMD="chrome-browser"
else
    echo "ERROR: No Chrome/Chromium browser found!"; exit 1
fi

nohup sudo -u ga $CHROME_CMD \
    --no-first-run --no-default-browser-check --disable-sync --no-sandbox \
    --disable-gpu --disable-dev-shm-usage --window-size=1920,1080 \
    --disable-infobars --password-store=basic \
    "http://localhost/opensis/" > /home/ga/chrome_opensis.log 2>&1 &

sleep 5
for i in {1..30}; do
    if wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then echo "Browser window detected"; break; fi
    sleep 1
done
wmctrl -a "Chrome" 2>/dev/null || wmctrl -a "Chromium" 2>/dev/null || true
wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Login: admin / Admin@123"
echo "Task: Full course launch — add Dr. Cruz, create APES101, section, enroll students, gradebook, grades, attendance"
