#!/bin/bash
set -e
echo "=== Setting up organize_subxsheet_collapse task ==="

# Define paths
SAMPLE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_SCENE_DIR="/home/ga/OpenToonz/projects"
OUTPUT_RENDER_DIR="/home/ga/OpenToonz/output"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure output directories exist
su - ga -c "mkdir -p $OUTPUT_SCENE_DIR"
su - ga -c "mkdir -p $OUTPUT_RENDER_DIR"

# Clean up previous runs
rm -f "$OUTPUT_SCENE_DIR/organized_scene.tnz" 2>/dev/null || true
rm -f "$OUTPUT_RENDER_DIR/organized_verify.png" 2>/dev/null || true

# Verify source scene exists
if [ ! -f "$SAMPLE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SAMPLE_SCENE"
    # Attempt to copy from backup location if available or alert
    if [ -f "/usr/share/opentoonz/stuff/projects/samples/scenes/dwanko_run.tnz" ]; then
         cp "/usr/share/opentoonz/stuff/projects/samples/scenes/dwanko_run.tnz" "$SAMPLE_SCENE"
    else
         echo "Critical error: Sample data missing."
         exit 1
    fi
fi

# Ensure OpenToonz is running and maximized
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    sleep 10
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "opentoonz"; then
        echo "OpenToonz window detected."
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="