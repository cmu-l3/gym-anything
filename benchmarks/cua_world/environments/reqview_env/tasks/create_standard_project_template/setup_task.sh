#!/bin/bash
set -e
echo "=== Setting up create_standard_project_template task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Clean up target directory to ensure fresh creation
TARGET_DIR="/home/ga/Documents/ReqView/StandardTemplate"
if [ -d "$TARGET_DIR" ]; then
    echo "Removing existing target directory..."
    rm -rf "$TARGET_DIR"
fi
# Ensure parent directory exists
mkdir -p "/home/ga/Documents/ReqView"
chown ga:ga "/home/ga/Documents/ReqView"

# 3. Launch ReqView
# We want to start fresh. If ReqView is running, kill it.
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Launch ReqView (it will likely open the last used project, which is fine)
# The agent knows how to do File > New Project.
echo "Launching ReqView..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority nohup '${REQVIEW_BIN}' > /dev/null 2>&1 &"

# 4. Wait for window and maximize
wait_for_reqview 60
maximize_window

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="