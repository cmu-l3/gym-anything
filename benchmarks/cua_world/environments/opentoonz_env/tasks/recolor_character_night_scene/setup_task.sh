#!/bin/bash
echo "=== Setting up recolor_character_night_scene task ==="

# Define paths
SCENE_PATH="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/night_scene"

# 1. Clean up previous output
echo "Cleaning output directory..."
rm -rf "$OUTPUT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Ensure OpenToonz is running and loads the scene
echo "Launching OpenToonz with scene: $SCENE_PATH"

# Kill existing instances
pkill -f opentoonz 2>/dev/null || true
sleep 2

# Create a launch script to handle the display and user context
cat > /tmp/launch_ot.sh << EOF
#!/bin/bash
export DISPLAY=:1
# Try snap bin or system bin
if [ -x /snap/bin/opentoonz ]; then
    /snap/bin/opentoonz "$SCENE_PATH" &
elif command -v opentoonz &> /dev/null; then
    opentoonz "$SCENE_PATH" &
else
    echo "OpenToonz not found!"
    exit 1
fi
EOF
chmod +x /tmp/launch_ot.sh

# Run as ga user
su - ga -c "/tmp/launch_ot.sh"

# 4. Wait for window and maximize
echo "Waiting for OpenToonz window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "opentoonz" > /dev/null; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Wait extra time for scene load
sleep 10

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss common startup popups
echo "Dismissing dialogs..."
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 5. Capture initial state
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="