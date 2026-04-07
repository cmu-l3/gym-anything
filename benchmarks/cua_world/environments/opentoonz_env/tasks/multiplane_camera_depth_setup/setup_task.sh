#!/bin/bash
echo "=== Setting up multiplane_camera_depth_setup task ==="

# Define paths
PROJECT_DIR="/home/ga/OpenToonz/projects/multiplane"
OUTPUT_DIR="/home/ga/OpenToonz/output/multiplane"

# clean up previous runs
echo "Cleaning directories..."
rm -rf "$PROJECT_DIR" "$OUTPUT_DIR"
su - ga -c "mkdir -p $PROJECT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# Ensure OpenToonz is running and ready
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "opentoonz"; then
            echo "OpenToonz started."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Close any open dialogs/popups
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Target Scene Path: $PROJECT_DIR/multiplane.tnz"
echo "Target Output Path: $OUTPUT_DIR"