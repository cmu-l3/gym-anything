#!/bin/bash
echo "=== Setting up productionize_pm2_services task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt
sudo chmod 666 /tmp/task_start_time.txt

# 2. Reset system state to ensure agent must perform the task
echo "Cleaning up any existing PM2 systemd configs..."
sudo systemctl disable pm2-root.service 2>/dev/null || true
sudo rm -f /etc/systemd/system/pm2-root.service
sudo systemctl daemon-reload

echo "Cleaning up PM2 dump state..."
sudo rm -f /root/.pm2/dump.pm2

echo "Cleaning up logrotate configs..."
sudo su -c "pm2 uninstall pm2-logrotate 2>/dev/null || true"
sudo rm -f /etc/logrotate.d/pm2* /etc/logrotate.d/socioboard*

# 3. Ensure PM2 is actually running the Socioboard microservices under root
# If the services aren't running, the agent can't save them.
PM2_COUNT=$(sudo su -c "pm2 jlist 2>/dev/null | jq '. | length'")
if [ -z "$PM2_COUNT" ] || [ "$PM2_COUNT" -eq 0 ]; then
    echo "Starting Socioboard microservices via PM2..."
    sudo su -c "cd /opt/socioboard/socioboard-api/user && pm2 start app.js --name user"
    sudo su -c "cd /opt/socioboard/socioboard-api/feeds && pm2 start app.js --name feeds"
    sudo su -c "cd /opt/socioboard/socioboard-api/publish && pm2 start app.js --name publish"
    sudo su -c "cd /opt/socioboard/socioboard-api/notification && pm2 start app.js --name notification"
fi

# 4. Open Firefox to Socioboard dashboard
if ! wait_for_http "http://localhost/" 60; then
  echo "WARNING: Socioboard not fully reachable, proceeding anyway"
fi
open_socioboard_page "http://localhost/"

# 5. Open a terminal for the user to work in
echo "Opening terminal for the agent..."
su - ga -c "DISPLAY=:1 gnome-terminal --maximize &"
sleep 2

# Maximize Terminal just in case
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Take initial screenshot
take_screenshot /tmp/task_start.png
echo "=== Setup complete ==="