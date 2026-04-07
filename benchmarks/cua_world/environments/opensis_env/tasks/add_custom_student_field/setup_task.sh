#!/bin/bash
set -e
echo "=== Setting up add_custom_student_field task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Services are running
sudo systemctl start mariadb || true
sudo systemctl start apache2 || true

# Wait for database
for i in {1..30}; do
    if mysqladmin ping -u opensis_user -popensis_password_123 --silent; then
        break
    fi
    sleep 1
done

# Record initial state of custom fields to detect changes
# We check common table names for custom fields in OpenSIS
INITIAL_CAT_COUNT=$(mysql -u opensis_user -popensis_password_123 opensis -N -e "SELECT COUNT(*) FROM custom_field_categories" 2>/dev/null || echo "0")
INITIAL_FIELD_COUNT=$(mysql -u opensis_user -popensis_password_123 opensis -N -e "SELECT COUNT(*) FROM custom_fields" 2>/dev/null || echo "0")

echo "$INITIAL_CAT_COUNT" > /tmp/initial_category_count.txt
echo "$INITIAL_FIELD_COUNT" > /tmp/initial_field_count.txt

echo "Initial Counts - Categories: $INITIAL_CAT_COUNT, Fields: $INITIAL_FIELD_COUNT"

# Ensure Chrome is clean and ready
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true

# Launch Chrome to OpenSIS Login
echo "Starting Chrome..."
if command -v google-chrome-stable &> /dev/null; then
    BROWSER="google-chrome-stable"
else
    BROWSER="chromium-browser"
fi

# Start browser maximized
su - ga -c "DISPLAY=:1 $BROWSER --start-maximized --no-sandbox --disable-gpu --password-store=basic http://localhost/opensis/ &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenSIS"; then
        echo "OpenSIS window detected"
        break
    fi
    sleep 1
done

# Ensure window focus
DISPLAY=:1 wmctrl -a "OpenSIS" 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="