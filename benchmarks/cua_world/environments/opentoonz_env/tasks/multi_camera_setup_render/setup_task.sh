#!/bin/bash
set -e
echo "=== Setting up multi_camera_setup_render task ==="

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
PROJECT_DIR="/home/ga/OpenToonz/projects"
OUTPUT_DIR="/home/ga/OpenToonz/outputs"

# Ensure directories exist
su - ga -c "mkdir -p $PROJECT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# Clean up previous task artifacts
rm -f "$PROJECT_DIR/multi_camera.tnz" 2>/dev/null || true
rm -f "$OUTPUT_DIR/closeup.png" 2>/dev/null || true
rm -f "$OUTPUT_DIR/closeup.xml" 2>/dev/null || true  # OpenToonz sometimes saves XML sidecars

# Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Fallback: try to find it elsewhere or fail
    FOUND=$(find /home/ga -name "dwanko_run.tnz" | head -n 1)
    if [ -n "$FOUND" ]; then
        echo "Found at $FOUND, copying..."
        mkdir -p "$(dirname "$SOURCE_SCENE")"
        cp "$FOUND" "$SOURCE_SCENE"
    else
        echo "CRITICAL: Could not find dwanko_run.tnz"
        exit 1
    fi
fi

# Ensure permissions
chown -R ga:ga "/home/ga/OpenToonz"

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Start OpenToonz
# We launch it empty so the agent has to load the scene (part of the task flow)
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz window detected"
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="