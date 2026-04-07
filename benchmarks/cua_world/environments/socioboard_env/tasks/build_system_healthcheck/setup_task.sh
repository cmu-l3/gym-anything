#!/bin/bash
echo "=== Setting up build_system_healthcheck task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure clean slate: remove any existing health check script
sudo rm -f /usr/local/bin/socioboard-health.sh

# Ensure the system is in a perfectly healthy state to start
log "Ensuring all services are running..."
sudo systemctl start apache2 mariadb mongod
sleep 3

# Verify frontend is active (ensure baseline state is healthy)
if ! wait_for_http "http://localhost/" 60; then
  log "WARNING: Frontend did not return HTTP success in setup, but continuing."
else
  log "System is verified healthy."
fi

# Open a terminal for the agent to start scripting immediately
su - ga -c "DISPLAY=:1 gnome-terminal --maximize --working-directory=/home/ga &"
sleep 2

# Take initial screenshot as evidence of starting state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="