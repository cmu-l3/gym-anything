#!/bin/bash
# Setup script for build_slam_data_collection task
# Creates the project directory structure and launches Webots with an empty state.
# The agent must build the entire world and controller from scratch.

echo "=== Setting up build_slam_data_collection task ==="

source /workspace/scripts/task_utils.sh

WEBOTS_HOME=$(detect_webots_home)
if [ -z "$WEBOTS_HOME" ]; then
    echo "ERROR: Webots not found"
    exit 1
fi

export LIBGL_ALWAYS_SOFTWARE=1

# Kill any existing Webots instances
pkill -f "webots" 2>/dev/null || true
sleep 3

# Define project paths
PROJECT_DIR="/home/ga/webots_projects/slam_bench"
CTRL_DIR="$PROJECT_DIR/controllers/slam_logger"

# Create project structure (controller directory empty for agent to fill)
mkdir -p "$CTRL_DIR"

# Set permissions
chown -R ga:ga "/home/ga/webots_projects"

# Create Desktop directory if needed
mkdir -p /home/ga/Desktop
chown ga:ga /home/ga/Desktop

# Delete stale outputs BEFORE recording timestamp
rm -f /home/ga/Desktop/slam_benchmark.wbt
rm -f "$CTRL_DIR/slam_logger.py"
rm -f /tmp/slam_log.csv
rm -f /tmp/slam_benchmark_result.json

# Record task start timestamp (anti-gaming)
date +%s > /tmp/task_start_timestamp

# Launch Webots with NO world loaded (empty state — agent builds from scratch)
echo "Launching Webots with empty state..."
su - ga -c "DISPLAY=:1 LIBGL_ALWAYS_SOFTWARE=1 WEBOTS_HOME=$WEBOTS_HOME setsid $WEBOTS_HOME/webots --batch --mode=pause > /tmp/webots_task.log 2>&1 &"

# Wait for window to appear
wait_for_webots_window 60
sleep 5

# Focus and maximize the window
focus_webots
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss any remaining dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot to prove empty starting state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Agent must build a complete SLAM benchmark world and data-logging controller."
echo "World output: /home/ga/Desktop/slam_benchmark.wbt"
echo "Controller output: $CTRL_DIR/slam_logger.py"
