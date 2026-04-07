#!/bin/bash
# Export script for build_slam_data_collection task
# Collects file existence, sizes, timestamps, and basic content checks into a JSON.

echo "=== Exporting build_slam_data_collection result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Paths
CTRL_FILE="/home/ga/webots_projects/slam_bench/controllers/slam_logger/slam_logger.py"
WORLD_FILE="/home/ga/Desktop/slam_benchmark.wbt"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Controller file checks
CTRL_EXISTS="false"
CTRL_SIZE=0
CTRL_MTIME=0

if [ -f "$CTRL_FILE" ]; then
    CTRL_EXISTS="true"
    CTRL_SIZE=$(stat -c %s "$CTRL_FILE" 2>/dev/null || echo "0")
    CTRL_MTIME=$(stat -c %Y "$CTRL_FILE" 2>/dev/null || echo "0")
    echo "Controller found: $CTRL_FILE ($CTRL_SIZE bytes)"
else
    echo "Controller NOT found at: $CTRL_FILE"
fi

# World file checks
WORLD_EXISTS="false"
WORLD_SIZE=0
WORLD_MTIME=0

if [ -f "$WORLD_FILE" ]; then
    WORLD_EXISTS="true"
    WORLD_SIZE=$(stat -c %s "$WORLD_FILE" 2>/dev/null || echo "0")
    WORLD_MTIME=$(stat -c %Y "$WORLD_FILE" 2>/dev/null || echo "0")
    echo "World file found: $WORLD_FILE ($WORLD_SIZE bytes)"
else
    echo "World file NOT found at: $WORLD_FILE"
fi

# Check if Webots was running
APP_WAS_RUNNING="false"
if pgrep -f "webots" > /dev/null; then
    APP_WAS_RUNNING="true"
fi

# Write result JSON
cat > /tmp/slam_benchmark_result.json << EOF
{
    "controller_exists": $CTRL_EXISTS,
    "controller_size_bytes": $CTRL_SIZE,
    "controller_mtime": $CTRL_MTIME,
    "world_exists": $WORLD_EXISTS,
    "world_size_bytes": $WORLD_SIZE,
    "world_mtime": $WORLD_MTIME,
    "task_start_timestamp": $TASK_START,
    "app_was_running": $APP_WAS_RUNNING,
    "export_timestamp": $(date +%s)
}
EOF

chmod 666 /tmp/slam_benchmark_result.json 2>/dev/null || true

echo "Result JSON written to /tmp/slam_benchmark_result.json"
cat /tmp/slam_benchmark_result.json

echo "=== Export Complete ==="
