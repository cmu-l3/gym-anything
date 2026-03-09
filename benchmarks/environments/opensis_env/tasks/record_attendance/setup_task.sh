#!/bin/bash
set -euo pipefail

echo "=== Setting up record_attendance task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

xhost +local: 2>/dev/null || true

# Ensure services are running
systemctl is-active --quiet mariadb || systemctl start mariadb
systemctl is-active --quiet apache2 || systemctl start apache2
sleep 2

# Ensure Sample Student exists in database
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "INSERT INTO students (first_name, last_name, date_of_birth, gender, grade_level)
     SELECT 'Sample', 'Student', '2005-05-15', 'M', '10'
     WHERE NOT EXISTS (SELECT 1 FROM students WHERE first_name='Sample' AND last_name='Student');" \
    2>/dev/null || true

# Kill existing Chrome
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true
sleep 1

# Start Chrome
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser"
fi

nohup sudo -u ga $CHROME_CMD \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --window-size=1920,1080 \
    --disable-infobars \
    --password-store=basic \
    "http://localhost/opensis/" > /home/ga/chrome_opensis.log 2>&1 &

sleep 5

for i in {1..30}; do
    if wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        break
    fi
    sleep 1
done

wmctrl -a "Chrome" 2>/dev/null || wmctrl -a "Chromium" 2>/dev/null || true
wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo "=== Task setup complete ==="
echo ""
echo "Task: Record attendance for 'Sample Student'"
echo "  - Student: Sample Student"
echo "  - Date: Today"
echo "  - Status: Present"
