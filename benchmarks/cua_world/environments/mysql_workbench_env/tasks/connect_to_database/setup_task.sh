#!/bin/bash
# Setup script for connect_to_database task

echo "=== Setting up Connect to Database task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Ensure MySQL is running
if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Ensure MySQL Workbench is running
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi

# Focus the Workbench window
focus_workbench

# Record initial connection count
echo "Recording initial state..."
INITIAL_CONNECTIONS=$(count_workbench_connections)
echo "$INITIAL_CONNECTIONS" > /tmp/initial_connection_count
echo "Initial connection count: $INITIAL_CONNECTIONS"

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

# Clear any previous result files
rm -f /tmp/connection_result.json 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Agent should now create a new connection named 'SakilaDB'"
