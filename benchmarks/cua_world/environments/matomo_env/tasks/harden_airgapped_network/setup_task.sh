#!/bin/bash
# Setup script for Harden Air-gapped Network task

echo "=== Setting up Harden Air-gapped Network Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp (critical for anti-gaming)
date +%s > /tmp/task_start_timestamp

# Ensure Matomo container is running
if ! docker ps --format '{{.Names}}' | grep -q "matomo-app"; then
    echo "Starting Matomo containers..."
    cd /home/ga/matomo
    docker-compose up -d
    wait_for_matomo 120
fi

# Ensure config file exists and backup original state
echo "Verifying config file existence..."
if docker exec matomo-app test -f /var/www/html/config/config.ini.php; then
    echo "Config file exists."
    # Backup for restoration if needed (good practice, though env resets anyway)
    docker exec matomo-app cp /var/www/html/config/config.ini.php /var/www/html/config/config.ini.php.bak
else
    echo "ERROR: Config file not found in container!"
    exit 1
fi

# Record initial file timestamp
INITIAL_MTIME=$(docker exec matomo-app stat -c %Y /var/www/html/config/config.ini.php 2>/dev/null || echo "0")
echo "$INITIAL_MTIME" > /tmp/initial_config_mtime

# Open a terminal window for the agent
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=100x30 &"
    sleep 2
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Task: Disable internet features in Matomo configuration."
echo "Target: /var/www/html/config/config.ini.php inside 'matomo-app' container."