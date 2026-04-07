#!/bin/bash
set -e
echo "=== Setting up Configure Trusted Hosts Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp (critical for anti-gaming)
date +%s > /tmp/task_start_timestamp

# Ensure Matomo container is running
if ! docker ps | grep -q matomo-app; then
    echo "Starting Matomo containers..."
    cd /home/ga/matomo
    docker-compose up -d
    wait_for_matomo 120
fi

# Prepare the configuration file on the host to simulate a local server environment
# We copy it from the container to the host path specified in the task description
HOST_CONFIG_DIR="/var/www/html/config"
HOST_CONFIG_FILE="$HOST_CONFIG_DIR/config.ini.php"

echo "Preparing host environment..."
# Create directory structure
sudo mkdir -p "$HOST_CONFIG_DIR"

# Copy real config from container
echo "Extracting configuration from container..."
sudo docker cp matomo-app:/var/www/html/config/config.ini.php "$HOST_CONFIG_FILE"

# Ensure permissions allow ga user to edit with sudo (owned by root is fine if they use sudo)
# But let's make it look like a standard web server file (owned by www-data usually)
sudo chown -R 33:33 "/var/www/html" 2>/dev/null || sudo chown -R root:root "/var/www/html"
sudo chmod 644 "$HOST_CONFIG_FILE"

# Record initial state hash for "do nothing" detection
md5sum "$HOST_CONFIG_FILE" | cut -d' ' -f1 > /tmp/initial_config_hash

# Ensure terminal is ready or open
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --working-directory=/home/ga &"
    sleep 2
fi

# Maximize terminal for better visibility
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Config file placed at: $HOST_CONFIG_FILE"