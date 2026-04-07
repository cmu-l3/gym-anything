#!/bin/bash
set -e
echo "=== Setting up reverse_animation_xsheet_render task ==="

# Define paths
SCENE_PATH="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/reversed_animation"

# 1. Clean output directory
echo "Cleaning output directory: $OUTPUT_DIR"
if [ -d "$OUTPUT_DIR" ]; then
    rm -rf "$OUTPUT_DIR"
fi
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Verify scene exists
if [ ! -f "$SCENE_PATH" ]; then
    echo "ERROR: Scene file not found at $SCENE_PATH"
    # Attempt to use a fallback if the specific sample is missing (unlikely in this env)
    # but strictly checking ensures validity
    exit 1
fi

# 3. Record task start time for anti-gaming (file timestamp check)
date +%s > /tmp/task_start_time.txt

# 4. Launch OpenToonz with the scene
echo "Launching OpenToonz..."
# Kill any existing instances
pkill -f opentoonz 2>/dev/null || true
sleep 1

# Launch logic
LAUNCH_SCRIPT="/tmp/launch_ot.sh"
cat > "$LAUNCH_SCRIPT" << EOF
#!/bin/bash
export DISPLAY=:1
if [ -x /snap/bin/opentoonz ]; then
    /snap/bin/opentoonz "$SCENE_PATH" &
elif command -v opentoonz &> /dev/null; then
    opentoonz "$SCENE_PATH" &
else
    echo "OpenToonz executable not found"
    exit 1
fi
EOF
chmod +x "$LAUNCH_SCRIPT"
su - ga -c "$LAUNCH_SCRIPT"

# 5. Wait for window and maximize
echo "Waiting for OpenToonz window..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize to ensure UI is visible for agent
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# 6. Take initial screenshot
sleep 5
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="