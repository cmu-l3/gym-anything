#!/bin/bash
set -e
echo "=== Setting up add_school_rooms task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Services are running
echo "Starting services..."
systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Wait for DB
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# Determine SYEAR dynamically (OpenSIS logic: if month >= 8, syear=next_year)
CURRENT_YEAR=$(date +%Y)
CURRENT_MONTH=$(date +%m)
if [ "$CURRENT_MONTH" -ge 8 ]; then
    SYEAR=$((CURRENT_YEAR + 1))
else
    SYEAR=$CURRENT_YEAR
fi
echo "Calculated SYEAR: $SYEAR"

# Database Cleanup: Remove target rooms if they exist to ensure clean state
echo "Cleaning up existing target rooms..."
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "DELETE FROM rooms WHERE title IN ('SCI-201', 'COMP-305') AND school_id=1;" 2>/dev/null || true

# Ensure Admin has permissions for Rooms module
mysql -u opensis_user -p'opensis_password_123' opensis -e \
    "INSERT INTO profile_exceptions (profile_id, modname, can_use, can_edit) VALUES 
    (1, 'schoolsetup/Rooms.php', 'Y', 'Y'),
    (1, 'schoolsetup/SchoolSetup.php', 'Y', 'Y')
    ON DUPLICATE KEY UPDATE can_use='Y', can_edit='Y';" 2>/dev/null || true

# Record initial room count for anti-gaming verification
INITIAL_COUNT=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e \
    "SELECT COUNT(*) FROM rooms WHERE school_id=1;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_room_count.txt
echo "Initial room count: $INITIAL_COUNT"

# Prepare Browser
echo "Launching Chrome..."
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true
sleep 1

# Launch Chrome to OpenSIS login
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser"
fi

su - ga -c "DISPLAY=:1 $CHROME_CMD --no-sandbox --disable-gpu --window-size=1920,1080 'http://localhost/opensis/' &"
sleep 5

# Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i -E "chrome|chromium|opensis"; then
        echo "Chrome window detected"
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="