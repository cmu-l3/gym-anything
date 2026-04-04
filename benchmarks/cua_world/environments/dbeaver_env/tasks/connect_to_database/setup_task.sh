#!/bin/bash
# Setup script for connect_to_database task
# Records initial state before agent action

echo "=== Setting up Connect to Database Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure DBeaver is running
if [ "$(is_dbeaver_running)" = "false" ]; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus DBeaver window
focus_dbeaver

# Record initial connection state
echo "Recording initial state..."

# Check if any connections exist in DBeaver config
CONFIG_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver"
if [ -f "$CONFIG_DIR/data-sources.json" ]; then
    INITIAL_CONNECTIONS=$(grep -c '"id"' "$CONFIG_DIR/data-sources.json" 2>/dev/null || echo "0")
else
    INITIAL_CONNECTIONS=0
fi

echo "$INITIAL_CONNECTIONS" > /tmp/initial_connection_count

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "Initial connections: $INITIAL_CONNECTIONS"
echo "=== Task Setup Complete ==="
