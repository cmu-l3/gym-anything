#!/bin/bash
echo "=== Setting up configure_pm2_ecosystem task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure background databases are running
systemctl start mariadb 2>/dev/null || true
systemctl start mongod 2>/dev/null || true

# Clean up any existing PM2 processes/state to ensure a clean slate
echo "Clearing existing PM2 state..."
sudo -u ga pm2 kill 2>/dev/null || true
sudo -u ga rm -rf /home/ga/.pm2/dump.pm2 2>/dev/null || true
pm2 kill 2>/dev/null || true

# Remove any pre-existing target files
rm -f /home/ga/ecosystem.config.js 2>/dev/null || true
rm -f /home/ga/pm2_status.txt 2>/dev/null || true

# Ensure proper ownership of the workspace
chown -R ga:ga /opt/socioboard 2>/dev/null || true
chown ga:ga /home/ga 2>/dev/null || true

# Open a terminal for the agent to use
echo "Launching terminal..."
sudo -u ga DISPLAY=:1 gnome-terminal --working-directory=/home/ga &
sleep 4

# Maximize the terminal window for better visibility
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="