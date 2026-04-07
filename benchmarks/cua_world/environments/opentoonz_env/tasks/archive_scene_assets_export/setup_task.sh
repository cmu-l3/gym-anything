#!/bin/bash
echo "=== Setting up archive_scene_assets_export task ==="

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/handoff_package"

# 1. Clean output state
# Remove the output directory to ensure we are checking fresh work
echo "Cleaning output directory..."
rm -rf "$OUTPUT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Verify source data
# Ensure the sample scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Try to copy from backup if missing (standard OpenToonz sample location)
    if [ -f "/usr/share/opentoonz/stuff/projects/samples/scenes/dwanko_run.tnz" ]; then
        su - ga -c "cp /usr/share/opentoonz/stuff/projects/samples/scenes/dwanko_run.tnz $SOURCE_SCENE"
        echo "Restored source scene from backup."
    else
        echo "CRITICAL: Could not locate source scene."
        # We continue anyway, hoping the agent or environment can recover, or fail gracefully
    fi
fi

# 3. Record Anti-Gaming Timestamp
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 4. Launch Application
echo "Launching OpenToonz..."
if ! pgrep -f "opentoonz" > /dev/null; then
    # Launch as user 'ga'
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 5. Window Management
# Maximize to ensure agent can see menus
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 6. Capture Initial State
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="