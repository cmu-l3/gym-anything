#!/bin/bash
set -e
echo "=== Setting up Blueprint Style Recolor Task ==="

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/blueprint"

# 1. Prepare Output Directory
# Ensure it exists and is completely empty to prevent false positives
echo "Clearing output directory..."
if [ -d "$OUTPUT_DIR" ]; then
    rm -rf "$OUTPUT_DIR"
fi
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Verify Data
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Try to copy from backup/installation if missing
    if [ -f "/usr/share/opentoonz/stuff/projects/samples/scenes/dwanko_run.tnz" ]; then
        cp "/usr/share/opentoonz/stuff/projects/samples/scenes/dwanko_run.tnz" "$SOURCE_SCENE"
    else
        echo "CRITICAL: Could not locate dwanko_run.tnz"
        exit 1
    fi
fi

# 3. Record Initial State
# Timestamp for anti-gaming (checking file modification times)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Launch Application
echo "Launching OpenToonz..."
# Check if already running
if ! pgrep -f "OpenToonz" > /dev/null; then
    # Launch in background as user 'ga'
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window to appear
    echo "Waiting for OpenToonz window..."
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz detected."
            break
        fi
        sleep 1
    done
fi

# 5. Window Management
# Maximize and focus for the agent
sleep 5
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 6. Capture Evidence
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="