#!/bin/bash
set -e
echo "=== Setting up composite_drop_shadow_fx task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Directories
OUTPUT_DIR="/home/ga/OpenToonz/output/shadow"
SAMPLE_DIR="/home/ga/OpenToonz/samples"
SCENE_FILE="$SAMPLE_DIR/dwanko_run.tnz"

# Ensure output directory exists and is empty
su - ga -c "mkdir -p $OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.png "$OUTPUT_DIR"/*.tga 2>/dev/null || true

# Verify source scene exists
if [ ! -f "$SCENE_FILE" ]; then
    echo "ERROR: Source scene $SCENE_FILE not found."
    # Attempt to restore from backup or download if needed (assuming env has it)
    exit 1
fi

# Ensure OpenToonz is ready (kill existing)
pkill -f opentoonz 2>/dev/null || true
sleep 1

# Launch OpenToonz with the specific scene
echo "Launching OpenToonz with scene..."
# We launch via su - ga to ensure correct user context
su - ga -c "DISPLAY=:1 opentoonz '$SCENE_FILE' &"

# Wait for window
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "OpenToonz window detected."
        break
    fi
    sleep 1
done

# Wait for load to finish
sleep 10

# Dismiss startup dialogs if any
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="