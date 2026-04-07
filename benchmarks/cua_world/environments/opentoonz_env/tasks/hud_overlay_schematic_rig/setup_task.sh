#!/bin/bash
echo "=== Setting up hud_overlay_schematic_rig task ==="

# Define paths
SAMPLE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
PROJECT_DIR="/home/ga/OpenToonz/projects/hud_test"
OUTPUT_DIR="/home/ga/OpenToonz/output/hud_test"

# Ensure directories exist and are owned by ga
su - ga -c "mkdir -p $PROJECT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# Clean up previous runs
rm -f "$PROJECT_DIR/hud_test.tnz" 2>/dev/null || true
rm -f "$OUTPUT_DIR"/*.png 2>/dev/null || true

# Verify sample scene exists
if [ ! -f "$SAMPLE_SCENE" ]; then
    echo "ERROR: Sample scene not found at $SAMPLE_SCENE"
    # Try to copy from backup location if available, otherwise fail
    if [ -f "/opt/opentoonz/stuff/projects/samples/scenes/dwanko_run.tnz" ]; then
         cp "/opt/opentoonz/stuff/projects/samples/scenes/dwanko_run.tnz" "$SAMPLE_SCENE"
    fi
fi

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure OpenToonz is running and focused
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            break
        fi
        sleep 1
    done
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Close any existing dialogs (startup popup)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Sample scene: $SAMPLE_SCENE"
echo "Target project: $PROJECT_DIR"
echo "Target output: $OUTPUT_DIR"