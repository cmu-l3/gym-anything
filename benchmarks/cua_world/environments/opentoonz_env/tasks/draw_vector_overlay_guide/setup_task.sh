#!/bin/bash
set -e
echo "=== Setting up draw_vector_overlay_guide task ==="

# Define paths
SCENE_PATH="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/guide_overlay"
PROJECT_ROOT="/home/ga/OpenToonz/sandbox"

# 1. Clean up previous run artifacts
# Remove output directory content
if [ -d "$OUTPUT_DIR" ]; then
    rm -rf "$OUTPUT_DIR"
fi
su - ga -c "mkdir -p $OUTPUT_DIR"

# Remove any previous .pli files (Vector Levels) created in the sandbox/drawings that might confuse verification
# We assume the user is working in the default sandbox or similar structure
# We won't delete ALL pli files (might break the scene), but we'll record the current state
find /home/ga/OpenToonz -name "*.pli" > /tmp/initial_pli_files.txt

# 2. Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Ensure OpenToonz is running and ready
# We will launch OpenToonz with the specific scene to save the agent some time and ensure correct starting state
echo "Launching OpenToonz with scene: $SCENE_PATH"

# Kill any existing instances
pkill -f opentoonz || true
sleep 2

# Launch
if [ -x /snap/bin/opentoonz ]; then
    su - ga -c "DISPLAY=:1 /snap/bin/opentoonz '$SCENE_PATH' &"
elif command -v opentoonz &> /dev/null; then
    su - ga -c "DISPLAY=:1 opentoonz '$SCENE_PATH' &"
else
    echo "Error: OpenToonz executable not found"
    exit 1
fi

# Wait for window
echo "Waiting for OpenToonz window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss startup dialogs if any (Enter/Esc sequence)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# 4. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="