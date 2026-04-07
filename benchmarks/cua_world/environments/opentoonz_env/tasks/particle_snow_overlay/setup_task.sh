#!/bin/bash
set -e
echo "=== Setting up particle_snow_overlay task ==="

# Define paths
SCENE_PATH="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/particle_snow"

# 1. Clean previous state
echo "Cleaning output directory..."
su - ga -c "mkdir -p $OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/* 2>/dev/null || true

# 2. Verify source scene exists
if [ ! -f "$SCENE_PATH" ]; then
    echo "ERROR: Scene file not found at $SCENE_PATH"
    # Attempt to restore from backup or find alternative if generic path fails
    # (Assuming environment is set up correctly, but being robust)
    FOUND=$(find /home/ga -name "dwanko_run.tnz" | head -1)
    if [ -n "$FOUND" ]; then
        SCENE_PATH="$FOUND"
        echo "Found scene at alternative path: $SCENE_PATH"
    else
        echo "FATAL: Could not find dwanko_run.tnz"
        exit 1
    fi
fi

# 3. Record initial state of the scene file (to detect modification later)
# FX addition modifies the .tnz XML structure
SCENE_INITIAL_HASH=$(md5sum "$SCENE_PATH" | awk '{print $1}')
echo "$SCENE_INITIAL_HASH" > /tmp/scene_initial_hash.txt
echo "Initial scene hash: $SCENE_INITIAL_HASH"

# 4. Record task start time (for anti-gaming file timestamp check)
date +%s > /tmp/task_start_time.txt

# 5. Launch OpenToonz with the scene
echo "Launching OpenToonz with scene: $SCENE_PATH"

# Kill any existing instances
pkill -f opentoonz 2>/dev/null || true
sleep 2

# Helper script to launch
cat > /tmp/launch_ot.sh << EOF
#!/bin/bash
export DISPLAY=:1
if [ -x /snap/bin/opentoonz ]; then
    /snap/bin/opentoonz "$SCENE_PATH"
elif command -v opentoonz >/dev/null; then
    opentoonz "$SCENE_PATH"
else
    echo "OpenToonz executable not found"
    exit 1
fi
EOF
chmod +x /tmp/launch_ot.sh

# Launch in background as user 'ga'
su - ga -c "/tmp/launch_ot.sh" > /tmp/opentoonz.log 2>&1 &

# 6. Wait for window and maximize
echo "Waiting for OpenToonz window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "opentoonz" > /dev/null; then
        echo "Window detected."
        break
    fi
    sleep 1
done

sleep 5
# Dismiss potential startup popups (e.g., "Scene is modified", "Updates")
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 1

# Maximize
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 7. Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="