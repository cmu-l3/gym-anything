#!/bin/bash
set -e
echo "=== Setting up create_substitute_profile task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure MySQL/MariaDB is running
service mariadb start 2>/dev/null || service mysql start 2>/dev/null || true
sleep 3

# Ensure Apache is running
service apache2 start 2>/dev/null || true

# DATABASE PREPARATION
# Remove 'Substitute' profile if it already exists to ensure a clean state
echo "Cleaning up database..."
mysql -u opensis_user -p'opensis_password_123' opensis -e "DELETE FROM user_profiles WHERE title='Substitute';" 2>/dev/null || true
# Note: Cascading deletes usually handle profile_exceptions, but to be safe:
# We rely on the app logic or subsequent queries to handle orphans, but explicitly:
# We can't easily delete exceptions without knowing the ID, but since we deleted the profile, 
# any new profile will have a new ID.

# Record initial profile count
INITIAL_COUNT=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e "SELECT COUNT(*) FROM user_profiles" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_profile_count.txt

# LAUNCH BROWSER
# Kill any existing Chrome instances
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true

echo "Starting Chrome..."
# Launch Chrome as user 'ga' pointing to OpenSIS
if command -v google-chrome-stable &> /dev/null; then
    CHROME_CMD="google-chrome-stable"
elif command -v chromium-browser &> /dev/null; then
    CHROME_CMD="chromium-browser"
else
    CHROME_CMD="chrome-browser"
fi

su - ga -c "DISPLAY=:1 $CHROME_CMD --start-maximized --no-sandbox http://localhost/opensis/ &"
sleep 5

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Chrome\|Chromium\|OpenSIS"; then
        echo "Browser window detected"
        break
    fi
    sleep 1
done

# Ensure window is maximized and focused
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || DISPLAY=:1 wmctrl -a "Chromium" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="