#!/bin/bash
set -e
echo "=== Setting up cinematic_vignette_composite task ==="

# Define paths
SCENE_PATH="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/vignette"

# 1. Clean previous outputs
echo "Cleaning output directory..."
su - ga -c "mkdir -p $OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/* 2>/dev/null || true

# 2. Verify source scene exists
if [ ! -f "$SCENE_PATH" ]; then
    echo "ERROR: Source scene not found at $SCENE_PATH"
    # Attempt to restore from backup or download if missing (resilience)
    # For now, just exit as this is critical
    exit 1
fi

# 3. Record task start timestamp for anti-gaming
date +%s > /tmp/task_start_timestamp

# 4. Launch OpenToonz
# We launch it empty or with the scene. Let's launch with the scene to ensure correct starting resolution
# but the agent still needs to interact with it.
echo "Launching OpenToonz..."
if pgrep -f "opentoonz" > /dev/null; then
    pkill -f "opentoonz" 2>/dev/null || true
    sleep 2
fi

# Launch as user 'ga'
# We use a wrapper or direct call depending on installation
LAUNCH_CMD="opentoonz"
if [ -x "/snap/bin/opentoonz" ]; then
    LAUNCH_CMD="/snap/bin/opentoonz"
fi

# Start OpenToonz with the scene file
su - ga -c "DISPLAY=:1 $LAUNCH_CMD \"$SCENE_PATH\" &"

# 5. Wait for window and maximize
echo "Waiting for OpenToonz window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 6. Dismiss startup dialogs (if any remain)
sleep 5
# Press Escape a few times to clear "Scene settings" or "Welcome" popups
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 7. Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="