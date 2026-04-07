#!/bin/bash
set -e
echo "=== Setting up create_scene_template task ==="

# Define target paths
TARGET_DIR="/home/ga/OpenToonz/projects/ep01_sc010"

# Clean up any previous attempts to ensure a fresh start
if [ -d "$TARGET_DIR" ]; then
    echo "Cleaning up existing directory: $TARGET_DIR"
    rm -rf "$TARGET_DIR"
fi

# Ensure parent directory exists
su - ga -c "mkdir -p /home/ga/OpenToonz/projects"

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Start OpenToonz if not running
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &" || su - ga -c "DISPLAY=:1 opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "opentoonz"; then
            echo "OpenToonz window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss any startup dialogs (Esc key usually works)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="