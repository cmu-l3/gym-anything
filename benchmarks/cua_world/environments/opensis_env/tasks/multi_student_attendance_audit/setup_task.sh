#!/bin/bash
set -euo pipefail

echo "=== Setting up multi_student_attendance_audit task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

xhost +local: 2>/dev/null || true

echo "Checking services..."
systemctl is-active --quiet mariadb || systemctl start mariadb
systemctl is-active --quiet apache2 || systemctl start apache2
sleep 2

echo "Seeding target students..."
mysql -u root opensis 2>/dev/null <<'SEED_SQL' || true
DELETE FROM attendance WHERE student_id IN (
  SELECT student_id FROM students WHERE
    (first_name='Miguel' AND last_name='Santos') OR
    (first_name='Aisha'  AND last_name='Patel')  OR
    (first_name='Dmitri' AND last_name='Volkov')
);
DELETE FROM grades WHERE student_id IN (
  SELECT student_id FROM students WHERE
    (first_name='Miguel' AND last_name='Santos') OR
    (first_name='Aisha'  AND last_name='Patel')  OR
    (first_name='Dmitri' AND last_name='Volkov')
);
DELETE FROM students WHERE
  (first_name='Miguel' AND last_name='Santos') OR
  (first_name='Aisha'  AND last_name='Patel')  OR
  (first_name='Dmitri' AND last_name='Volkov');

INSERT INTO students (first_name, last_name, date_of_birth, gender, grade_level)
VALUES
  ('Miguel', 'Santos', '2006-05-12', 'M', '10'),
  ('Aisha',  'Patel',  '2006-08-29', 'F', '10'),
  ('Dmitri', 'Volkov', '2006-03-17', 'M', '10');
SEED_SQL
echo "Students seeded."

# Record baseline state
date +%s > /tmp/task_start_timestamp
mysql -u opensis_user -p'opensis_password_123' opensis \
  -e "SELECT COUNT(*) FROM attendance WHERE attendance_date='2024-11-04'" \
  2>/dev/null | tail -1 > /tmp/initial_attendance_count || echo "0" > /tmp/initial_attendance_count
echo "Baseline: $(cat /tmp/initial_attendance_count) attendance records on 2024-11-04"

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
echo "Task: Record attendance 2024-11-04 — Miguel Santos: Present, Aisha Patel: Absent, Dmitri Volkov: Tardy"
