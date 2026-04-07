#!/bin/bash
set -e
echo "=== Setting up Configure Attendance Codes task ==="

# Source task utilities if available, otherwise define minimal helpers
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Ensure services are running
echo "Checking database..."
service mariadb start 2>/dev/null || systemctl start mariadb || true
service apache2 start 2>/dev/null || systemctl start apache2 || true

# Wait for DB
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "Database ready."
        break
    fi
    sleep 1
done

# 3. Determine current school year (SYEAR)
# OpenSIS usually uses the ending year as the SYEAR (e.g. 2024-2025 -> 2025)
# We can fetch the active school year from the database to be safe
SYEAR=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e "SELECT syear FROM schools WHERE id=1 LIMIT 1" 2>/dev/null || echo "")

if [ -z "$SYEAR" ]; then
    # Fallback calculation
    CURRENT_YEAR=$(date +%Y)
    CURRENT_MONTH=$(date +%m)
    if [ "$CURRENT_MONTH" -ge 8 ]; then
        SYEAR=$((CURRENT_YEAR + 1))
    else
        SYEAR=$CURRENT_YEAR
    fi
fi
echo "Target School Year: $SYEAR" > /tmp/target_syear.txt

# 4. Clean State: Remove target codes if they already exist
echo "Cleaning up any existing target codes..."
mysql -u opensis_user -p'opensis_password_123' opensis -e "DELETE FROM attendance_codes WHERE short_name IN ('HD', 'VA') AND school_id=1;" 2>/dev/null || true

# 5. Record initial state (count of attendance codes)
INITIAL_COUNT=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e "SELECT COUNT(*) FROM attendance_codes WHERE school_id=1 AND syear='$SYEAR'" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_count.txt
echo "Initial code count: $INITIAL_COUNT"

# 6. Ensure permissions (Admin user can access School Setup)
mysql -u opensis_user -p'opensis_password_123' opensis -e "UPDATE profile_exceptions SET can_use='Y', can_edit='Y' WHERE profile_id=1 AND modname IN ('schoolsetup/AttendanceCodes.php', 'schoolsetup/SchoolSetup.php');" 2>/dev/null || true

# 7. Launch Chrome
echo "Launching Chrome..."
pkill -f chrome 2>/dev/null || true

# Launch Chrome as ga user
su - ga -c "DISPLAY=:1 google-chrome-stable --no-sandbox --disable-gpu --start-maximized --no-first-run 'http://localhost/opensis/' &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "chrome"; then
        echo "Chrome window detected"
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 8. Automate Login (Helper)
sleep 5
echo "Automating login..."
DISPLAY=:1 xdotool key ctrl+l
sleep 0.5
DISPLAY=:1 xdotool type "http://localhost/opensis/"
DISPLAY=:1 xdotool key Return
sleep 3

# Attempt to focus username field (tabbing usually works)
DISPLAY=:1 xdotool key Tab
sleep 0.2
DISPLAY=:1 xdotool type "admin"
DISPLAY=:1 xdotool key Tab
sleep 0.2
DISPLAY=:1 xdotool type "Admin@123"
DISPLAY=:1 xdotool key Return

# 9. Initial Screenshot
sleep 5
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="