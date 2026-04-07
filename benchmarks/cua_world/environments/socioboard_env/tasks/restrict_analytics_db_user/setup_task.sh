#!/bin/bash
echo "=== Setting up restrict_analytics_db_user task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure MariaDB is running
if ! systemctl is-active --quiet mariadb; then
    echo "Starting MariaDB..."
    systemctl start mariadb
    sleep 3
fi

# Create the vulnerable state (Agent must fix this)
echo "Creating overly permissive analytics_user account..."
mysql -u root << 'EOSQL'
-- Clean up in case of a retry
DROP USER IF EXISTS 'analytics_user'@'localhost';

-- Create user with an unknown initial password
CREATE USER 'analytics_user'@'localhost' IDENTIFIED BY 'OldPassword123!';

-- Intentionally grant excessive, dangerous privileges
GRANT ALL PRIVILEGES ON `socioboard`.* TO 'analytics_user'@'localhost';
FLUSH PRIVILEGES;
EOSQL

# Verify the vulnerable setup was successful
TEST_GRANT=$(mysql -u root -N -e "SHOW GRANTS FOR 'analytics_user'@'localhost';" 2>/dev/null | grep -i "ALL PRIVILEGES")
if [ -z "$TEST_GRANT" ]; then
    echo "WARNING: Failed to setup the vulnerable user state!"
else
    echo "Vulnerable user 'analytics_user' created successfully with ALL PRIVILEGES."
fi

# Open a terminal for the agent to work in
if ! pgrep -f "gnome-terminal" > /dev/null; then
    echo "Opening terminal..."
    su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
    sleep 3
fi

# Ensure terminal is focused and maximized
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Clear any previous agent artifacts
rm -f /tmp/restrict_user_result.json 2>/dev/null || true

# Take initial screenshot for evidence
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured."
fi

echo "=== Task setup complete ==="