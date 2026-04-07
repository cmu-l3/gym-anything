#!/bin/bash
# Export script for write_epuck_controller task
# Checks for the presence of the written controller and the saved world.

echo "=== Exporting write_epuck_controller result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Paths
CTRL_FILE="/home/ga/webots_projects/epuck_obstacle/controllers/obstacle_avoider/obstacle_avoider.py"
WORLD_FILE="/home/ga/Desktop/epuck_avoidance.wbt"

# File checks
CTRL_EXISTS="false"
CTRL_SIZE=0
CTRL_MTIME=0

WORLD_EXISTS="false"
WORLD_SIZE=0

if [ -f "$CTRL_FILE" ]; then
    CTRL_EXISTS="true"
    CTRL_SIZE=$(stat -c %s "$CTRL_FILE" 2>/dev/null || echo "0")
    CTRL_MTIME=$(stat -c %Y "$CTRL_FILE" 2>/dev/null || echo "0")
    echo "Controller found: $CTRL_FILE ($CTRL_SIZE bytes)"
else
    echo "Controller NOT found at: $CTRL_FILE"
fi

if [ -f "$WORLD_FILE" ]; then
    WORLD_EXISTS="true"
    WORLD_SIZE=$(stat -c %s "$WORLD_FILE" 2>/dev/null || echo "0")
    echo "World file found: $WORLD_FILE ($WORLD_SIZE bytes)"
else
    echo "World file NOT found at: $WORLD_FILE"
fi

# Task Start Time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Write result JSON
cat > /tmp/write_epuck_controller_result.json << EOF
{
    "controller_exists": $CTRL_EXISTS,
    "controller_size_bytes": $CTRL_SIZE,
    "controller_mtime": $CTRL_MTIME,
    "world_exists": $WORLD_EXISTS,
    "world_size_bytes": $WORLD_SIZE,
    "task_start_timestamp": $TASK_START,
    "export_timestamp": "$(date +%s)"
}
EOF

echo "Result JSON written to /tmp/write_epuck_controller_result.json"
cat /tmp/write_epuck_controller_result.json

echo "=== Export Complete ==="