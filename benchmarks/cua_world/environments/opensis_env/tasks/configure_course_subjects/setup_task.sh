#!/bin/bash
set -euo pipefail

echo "=== Setting up configure_course_subjects task ==="

# Define paths and credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
systemctl is-active --quiet mariadb || systemctl start mariadb
systemctl is-active --quiet apache2 || systemctl start apache2
sleep 3

# Wait for MySQL to be ready
for i in {1..30}; do
    if mysqladmin ping -u"$DB_USER" -p"$DB_PASS" --silent; then
        break
    fi
    sleep 1
done

# Determine correct table name (schema variation handling)
TABLE_NAME="course_subjects"
if ! mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "DESCRIBE $TABLE_NAME" >/dev/null 2>&1; then
    if mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "DESCRIBE subjects" >/dev/null 2>&1; then
        TABLE_NAME="subjects"
    fi
fi
echo "$TABLE_NAME" > /tmp/subject_table_name.txt

# Clean up any pre-existing target data to ensure fresh start
mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "DELETE FROM $TABLE_NAME WHERE title IN ('Computer Science', 'Fine Arts');" 2>/dev/null || true

# Record initial state metrics for anti-gaming
INITIAL_COUNT=$(mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT COUNT(*) FROM $TABLE_NAME;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_subject_count.txt

# Get Max ID to detect new insertions
INITIAL_MAX_ID=$(mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT COALESCE(MAX(subject_id), 0) FROM $TABLE_NAME;" 2>/dev/null || echo "0")
echo "$INITIAL_MAX_ID" > /tmp/initial_max_id.txt

# Prepare Browser
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true

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

# Wait for window
sleep 5
for i in {1..30}; do
    if wmctrl -l | grep -qi "chrome\|chromium\|opensis"; then
        break
    fi
    sleep 1
done

# Maximize and focus
wmctrl -a "Chrome" 2>/dev/null || wmctrl -a "Chromium" 2>/dev/null || true
wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Target table identified as: $TABLE_NAME"
echo "Initial count: $INITIAL_COUNT"
echo "Initial max ID: $INITIAL_MAX_ID"