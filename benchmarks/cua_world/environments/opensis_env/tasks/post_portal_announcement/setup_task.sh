#!/bin/bash
set -e

echo "=== Setting up post_portal_announcement task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure services are running
systemctl start mariadb 2>/dev/null || true
systemctl start apache2 2>/dev/null || true

# Wait for database
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        break
    fi
    sleep 1
done

# Clean up any existing notes with this title to ensure we verify a NEW note
echo "Cleaning up old notes..."
mysql -u opensis_user -p'opensis_password_123' opensis -e "DELETE FROM portal_notes WHERE title='Spring Science Fair';" 2>/dev/null || true

# Record initial count of portal notes
INITIAL_COUNT=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e "SELECT COUNT(*) FROM portal_notes" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_notes_count.txt

# Ensure Chrome is running and focused
if ! pgrep -f "chrome" > /dev/null; then
    echo "Starting Chrome..."
    # Launch Chrome as ga user
    su - ga -c "DISPLAY=:1 google-chrome-stable --no-sandbox --start-maximized http://localhost/opensis/ &"
    sleep 5
fi

# Maximize and focus Chrome
DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="