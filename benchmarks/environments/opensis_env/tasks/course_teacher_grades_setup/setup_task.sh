#!/bin/bash
set -euo pipefail

echo "=== Setting up course_teacher_grades_setup task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

xhost +local: 2>/dev/null || true

echo "Checking services..."
systemctl is-active --quiet mariadb || systemctl start mariadb
systemctl is-active --quiet apache2 || systemctl start apache2
sleep 2

echo "Seeding students and cleaning test data..."
mysql -u root opensis 2>/dev/null <<'SEED_SQL' || true
DELETE FROM staff WHERE first_name='Evelyn' AND last_name='Park';

DELETE grades FROM grades
  INNER JOIN courses ON grades.course_id = courses.course_id
  WHERE courses.course_code = 'BIO401';
DELETE FROM courses WHERE course_code = 'BIO401';

DELETE grades FROM grades
  INNER JOIN students ON grades.student_id = students.student_id
  WHERE grades.assignment_name = 'Lab Practical'
    AND ((students.first_name='Sophie' AND students.last_name='Walsh') OR
         (students.first_name='Kevin') OR
         (students.first_name='Maya'   AND students.last_name='Rodriguez'));

DELETE FROM attendance WHERE student_id IN (
  SELECT student_id FROM students WHERE
    (first_name='Sophie' AND last_name='Walsh') OR
    (first_name='Kevin'  AND (last_name='OBrien' OR last_name="O'Brien")) OR
    (first_name='Maya'   AND last_name='Rodriguez')
);
DELETE FROM grades WHERE student_id IN (
  SELECT student_id FROM students WHERE
    (first_name='Sophie' AND last_name='Walsh') OR
    (first_name='Kevin'  AND (last_name='OBrien' OR last_name="O'Brien")) OR
    (first_name='Maya'   AND last_name='Rodriguez')
);
DELETE FROM students WHERE
  (first_name='Sophie' AND last_name='Walsh') OR
  (first_name='Kevin'  AND (last_name='OBrien' OR last_name="O'Brien")) OR
  (first_name='Maya'   AND last_name='Rodriguez');

INSERT INTO students (first_name, last_name, date_of_birth, gender, grade_level)
VALUES
  ('Sophie', 'Walsh',     '2005-04-10', 'F', '12'),
  ('Kevin',  "O'Brien",   '2005-07-23', 'M', '12'),
  ('Maya',   'Rodriguez', '2005-11-05', 'F', '12');
SEED_SQL
echo "Setup complete."

# Record baseline state
date +%s > /tmp/task_start_timestamp
mysql -u opensis_user -p'opensis_password_123' opensis \
  -e "SELECT COUNT(*) FROM staff" 2>/dev/null | tail -1 > /tmp/initial_staff_count || echo "0" > /tmp/initial_staff_count
mysql -u opensis_user -p'opensis_password_123' opensis \
  -e "SELECT COUNT(*) FROM courses" 2>/dev/null | tail -1 > /tmp/initial_course_count || echo "0" > /tmp/initial_course_count
mysql -u opensis_user -p'opensis_password_123' opensis \
  -e "SELECT COUNT(*) FROM grades" 2>/dev/null | tail -1 > /tmp/initial_grade_count || echo "0" > /tmp/initial_grade_count
echo "Baseline: $(cat /tmp/initial_staff_count) staff, $(cat /tmp/initial_course_count) courses, $(cat /tmp/initial_grade_count) grades"

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
echo "Task: Add Dr. Evelyn Park (Teacher), create BIO401, enter Lab Practical grades for Sophie/Kevin/Maya"
