#!/bin/bash
set -e
echo "=== Setting up task: configure_report_card_comments ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Database credentials
DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# Ensure MariaDB is running
if ! pgrep -f "mariadbd" > /dev/null && ! pgrep -f "mysqld" > /dev/null; then
    echo "Starting Database..."
    systemctl start mariadb 2>/dev/null || systemctl start mysql 2>/dev/null || true
    sleep 5
fi

# Ensure Apache is running
if ! pgrep -f "apache2" > /dev/null; then
    echo "Starting Web Server..."
    systemctl start apache2 2>/dev/null || true
    sleep 3
fi

# ANTI-GAMING: Clean state
# Remove specific comments if they already exist to ensure agent actually creates them
echo "Cleaning existing comments..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "DELETE FROM report_card_comments WHERE code IN ('PLE', 'MHW') AND school_id=1;" 2>/dev/null || true

# Record initial count (should be 0 for these specific codes)
INITIAL_COUNT=$(mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -N -e "SELECT COUNT(*) FROM report_card_comments WHERE code IN ('PLE', 'MHW') AND school_id=1;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_comment_count.txt

# Ensure Admin has access to Grades Setup (Prerequisite)
# Sometimes default installs might not have all granular permissions set
echo "Ensuring permissions..."
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF 2>/dev/null || true
INSERT INTO profile_exceptions (profile_id, modname, can_use, can_edit) VALUES
(1, 'grades/Grades.php', 'Y', 'Y'),
(1, 'grades/ReportCardComments.php', 'Y', 'Y')
ON DUPLICATE KEY UPDATE can_use='Y', can_edit='Y';
EOF

# Kill any existing Chrome instances
pkill -f chrome 2>/dev/null || true
pkill -f chromium 2>/dev/null || true
sleep 1

# Launch Browser
echo "Launching OpenSIS..."
# Check for launch script or use direct command
if [ -f "/home/ga/launch_opensis.sh" ]; then
    su - ga -c "/home/ga/launch_opensis.sh"
else
    # Fallback launch logic
    if command -v google-chrome-stable &> /dev/null; then
        CHROME_CMD="google-chrome-stable"
    elif command -v chromium-browser &> /dev/null; then
        CHROME_CMD="chromium-browser"
    else
        CHROME_CMD="chrome-browser" # Fallback
    fi
    
    su - ga -c "export DISPLAY=:1; $CHROME_CMD --start-maximized --no-sandbox --disable-gpu http://localhost/opensis &"
fi

# Wait for window
echo "Waiting for browser..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenSIS"; then
        echo "Browser detected."
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "OpenSIS" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenSIS" 2>/dev/null || true

# Screenshot initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="