#!/bin/bash
set -e
echo "=== Setting up Change Display Language task ==="

# 1. Record task start time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt

# 2. Snapshot initial configuration state
# We want to detect if config files change during the task
echo "Snapshotting initial config state..."
mkdir -p /tmp/initial_config
if [ -d "/home/ga/.jstock" ]; then
    # Save md5sums of all config files
    find /home/ga/.jstock -type f -exec md5sum {} + > /tmp/initial_config_checksums.txt 2>/dev/null || true
else
    echo "Warning: .jstock directory not found initially"
    touch /tmp/initial_config_checksums.txt
fi

# 3. Ensure JStock is clean and running
# Kill existing instances to start fresh
pkill -f "jstock.jar" 2>/dev/null || true
sleep 2

# Launch JStock
echo "Launching JStock..."
su - ga -c "setsid /usr/local/bin/launch-jstock > /tmp/jstock_task.log 2>&1 &"

# Wait for window
echo "Waiting for JStock window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "JStock"; then
        echo "JStock window detected"
        break
    fi
    sleep 1
done

# 4. Handle startup dialogs
sleep 5
# Press Enter to dismiss "JStock News" or "Welcome" dialogs
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 2

# 5. Maximize window for visibility
DISPLAY=:1 wmctrl -r "JStock" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# 6. Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="