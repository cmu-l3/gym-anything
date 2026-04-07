#!/bin/bash
# Setup script for Enable Legacy UTM Tracking task

echo "=== Setting up Enable Legacy UTM Tracking Task ==="
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure Matomo is running
if ! docker ps | grep -q matomo-app; then
    echo "Starting Matomo containers..."
    docker-compose -f /home/ga/matomo/docker-compose.yml up -d
    wait_for_matomo 120
fi

# Create a backup of config.ini.php (internal use only, not for agent)
# This allows us to verify if it changed later
docker exec matomo-app cat /var/www/html/config/config.ini.php > /tmp/config.ini.php.bak

# Open a terminal for the agent since this is a config task
echo "Opening terminal..."
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=100x30 &"
    sleep 2
fi

# Focus the terminal
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Also open a text editor with a hint or empty file to suggest editing tools are available
# (Optional, but helpful context)
# su - ga -c "DISPLAY=:1 gedit /home/ga/README.txt &"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="