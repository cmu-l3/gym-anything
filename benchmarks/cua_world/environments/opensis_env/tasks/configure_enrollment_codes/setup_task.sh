#!/bin/bash
set -e
echo "=== Setting up Configure Enrollment Codes task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
echo "Starting services..."
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Wait for MariaDB
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# Wait for Apache
for i in {1..20}; do
    if curl -s http://localhost/opensis/ >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# Database cleanup and setup
echo "Preparing database..."
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Get School ID (usually 1)
SCHOOL_ID=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -e "SELECT id FROM schools LIMIT 1" 2>/dev/null || echo "1")
SYEAR=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -e "SELECT syear FROM schools WHERE id=$SCHOOL_ID" 2>/dev/null || echo "2025")

# Clear existing enrollment codes for this school/year to ensure a clean test
# This prevents "already correct" state from giving free points
mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -e "DELETE FROM student_enrollment_codes WHERE syear='$SYEAR'" 2>/dev/null || true

# Record initial count (should be 0)
INITIAL_COUNT=$(mysql -u $DB_USER -p"$DB_PASS" $DB_NAME -N -e "SELECT COUNT(*) FROM student_enrollment_codes WHERE syear='$SYEAR'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_code_count.txt
echo "Initial enrollment code count: $INITIAL_COUNT"

# Launch Chrome
echo "Launching Chrome..."
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser"
fi

su - ga -c "DISPLAY=:1 $CHROME_CMD --no-sandbox --disable-gpu --start-maximized --password-store=basic 'http://localhost/opensis/' > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i -E "chrome|opensis|chromium"; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="