#!/bin/bash
set -e
echo "=== Setting up dailies_range_render_preview task ==="

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/dailies"

# 1. Clean and prepare output directory
echo "Cleaning output directory: $OUTPUT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"
# Remove any existing images to prevent false positives from previous runs
find "$OUTPUT_DIR" -type f \( -name "*.png" -o -name "*.tga" -o -name "*.tif" -o -name "*.jpg" \) -delete 2>/dev/null || true

# 2. Verify source scene exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Fallback: try to find it elsewhere or use a different sample if needed
    FOUND_SCENE=$(find /home/ga/OpenToonz -name "dwanko_run.tnz" | head -n 1)
    if [ -n "$FOUND_SCENE" ]; then
        SOURCE_SCENE="$FOUND_SCENE"
        echo "Found scene at alternate location: $SOURCE_SCENE"
    else
        echo "CRITICAL: Could not find sample scene."
        exit 1
    fi
fi

# 3. Record task start timestamp (Anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# 4. Launch OpenToonz
# We launch it *without* the file first to ensure a clean state, or *with* it if robust.
# Launching with file is friendlier for the agent in this specific task to ensure they start right.
echo "Launching OpenToonz with scene: $SOURCE_SCENE"

# Kill any existing instances
pkill -f opentoonz 2>/dev/null || true
sleep 2

# Launch logic
LAUNCH_CMD="opentoonz"
if [ -x "/snap/bin/opentoonz" ]; then
    LAUNCH_CMD="/snap/bin/opentoonz"
fi

# Run as ga user, detached
su - ga -c "DISPLAY=:1 $LAUNCH_CMD \"$SOURCE_SCENE\" &"

# 5. Wait for application window
echo "Waiting for OpenToonz window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "Window detected."
        break
    fi
    sleep 1
done
sleep 5 # Allow scene to load

# 6. Handle Dialogs (Popup handling)
echo "Dismissing startup dialogs..."
# Try pressing Escape/Enter a few times to clear "Scene settings" or "Welcome" popups
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 0.5
done

# 7. Maximize Window
echo "Maximizing window..."
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 8. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup Complete ==="
echo "Target Range: Frames 5-15"
echo "Target Resolution: 960x540"