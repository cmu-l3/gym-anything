#!/bin/bash
echo "=== Setting up Secure BI Database Provisioning task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure MariaDB is running
systemctl is-active --quiet mariadb || systemctl start mariadb
sleep 2

# Clean up any previous state to ensure a clean slate
echo "Cleaning up any pre-existing bi_viewer user or views..."
mysql -u root -e "DROP USER IF EXISTS 'bi_viewer'@'localhost';" 2>/dev/null || true
mysql -u root socioboard -e "DROP VIEW IF EXISTS bi_user_export;" 2>/dev/null || true
mysql -u root socioboard -e "DROP VIEW IF EXISTS bi_social_export;" 2>/dev/null || true
mysql -u root -e "FLUSH PRIVILEGES;" 2>/dev/null || true

# Remove old artifact if exists
rm -f /home/ga/bi_initial_extract.csv 2>/dev/null || true

# Launch terminal for the agent
if ! pgrep -f gnome-terminal > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --window --maximize &" 2>/dev/null || true
    sleep 3
fi

DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial state screenshot
take_screenshot /tmp/task_initial.png
chmod 644 /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="