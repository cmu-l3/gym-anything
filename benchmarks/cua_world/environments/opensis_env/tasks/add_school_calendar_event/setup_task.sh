#!/bin/bash
set -e
echo "=== Setting up add_school_calendar_event task ==="

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure services are running
echo "Checking services..."
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Wait for MariaDB
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "Database ready"
        break
    fi
    sleep 1
done

# 3. Clean State: Remove any existing event with similar title/date to prevent false positives
echo "Cleaning up any existing events..."
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Delete from calendar_events (standard OpenSIS table)
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "DELETE FROM calendar_events WHERE title LIKE '%Science Fair%' OR school_date = '2026-05-20';" 2>/dev/null || true

# 4. Start Browser
echo "Starting Chrome..."
pkill -f chrome 2>/dev/null || true

if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
else
    CHROME_CMD="chromium-browser"
fi

su - ga -c "DISPLAY=:1 $CHROME_CMD --no-sandbox --disable-gpu --start-maximized http://localhost/opensis/ &"

# 5. Wait for window and maximize
sleep 5
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Chrome\|Chromium"; then
        echo "Browser window found"
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="