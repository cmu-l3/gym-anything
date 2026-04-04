#!/bin/bash
set -euo pipefail

echo "=== Setting up transfer_student_intake task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

xhost +local: 2>/dev/null || true

echo "Checking services..."
systemctl is-active --quiet mariadb || systemctl start mariadb
systemctl is-active --quiet apache2 || systemctl start apache2
sleep 2

echo "Cleaning pre-existing test data..."
mysql -u root opensis 2>/dev/null <<'CLEANUP_SQL' || true
DELETE grades FROM grades
  INNER JOIN students ON grades.student_id = students.student_id
  WHERE students.first_name = 'Zara' AND students.last_name = 'Hoffman';
DELETE FROM students WHERE first_name = 'Zara' AND last_name = 'Hoffman';
DELETE FROM grades WHERE course_id IN (
  SELECT course_id FROM courses WHERE course_code IN ('CHEM301','ENG401','HIST201')
);
DELETE FROM courses WHERE course_code IN ('CHEM301','ENG401','HIST201');
CLEANUP_SQL

echo "Pre-existing test data cleaned."

# Record baseline state (CRITICAL for adversarial robustness)
date +%s > /tmp/task_start_timestamp
mysql -u opensis_user -p'opensis_password_123' opensis -e "SELECT COUNT(*) FROM students" 2>/dev/null | tail -1 > /tmp/initial_student_count || echo "0" > /tmp/initial_student_count
mysql -u opensis_user -p'opensis_password_123' opensis -e "SELECT COUNT(*) FROM courses" 2>/dev/null | tail -1 > /tmp/initial_course_count || echo "0" > /tmp/initial_course_count
mysql -u opensis_user -p'opensis_password_123' opensis -e "SELECT COUNT(*) FROM grades" 2>/dev/null | tail -1 > /tmp/initial_grade_count || echo "0" > /tmp/initial_grade_count
echo "Baseline: $(cat /tmp/initial_student_count) students, $(cat /tmp/initial_course_count) courses, $(cat /tmp/initial_grade_count) grades"

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

# Take initial screenshot
scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Login: admin / Admin@123"
echo "Task: Transfer intake for Zara Hoffman (Gr11) — create student, 3 courses (CHEM301/ENG401/HIST201), 3 grades"
