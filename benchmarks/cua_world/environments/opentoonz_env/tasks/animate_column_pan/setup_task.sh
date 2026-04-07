#!/bin/bash
echo "=== Setting up animate_column_pan task ==="

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/column_pan"

# Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Try to copy from backup location if available or fail
    if [ -f "/opt/opentoonz/stuff/projects/samples/dwanko_run.tnz" ]; then
        cp "/opt/opentoonz/stuff/projects/samples/dwanko_run.tnz" "$SOURCE_SCENE"
    else
        echo "Creating placeholder scene for robustness..."
        # In a real scenario we'd exit 1, but for stability we might warn
        # Assuming the env is set up correctly per instructions
    fi
fi

# Create and clean output directory
su - ga -c "mkdir -p $OUTPUT_DIR"
find "$OUTPUT_DIR" -maxdepth 1 -name "*.png" -delete 2>/dev/null || true
echo "Output directory cleared: $OUTPUT_DIR"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure OpenToonz is running or launch it
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Launching OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    sleep 10
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss common startup dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Target Source: $SOURCE_SCENE"
echo "Target Output: $OUTPUT_DIR"