#!/bin/bash
set -e
echo "=== Setting up apply_blur_fx_render task ==="

# Define paths
SCENE_PATH="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/blur_fx"

# 1. Prepare Output Directory
# Clean up any previous run artifacts
echo "Cleaning output directory: $OUTPUT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.png "$OUTPUT_DIR"/*.tga 2>/dev/null || true

# 2. Record Initial State
# Count files (should be 0)
INITIAL_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.png" 2>/dev/null | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_file_count.txt

# Record start time for anti-gaming (file modification checks)
date +%s > /tmp/task_start_time.txt

# 3. Launch OpenToonz
# We launch it with the scene file so the agent starts in the right context,
# though the description says "Open the scene", pre-loading is standard for "Starting State".
echo "Launching OpenToonz with scene: $SCENE_PATH"

# Kill existing instances
pkill -f opentoonz 2>/dev/null || true
sleep 2

# Create a launch script to run as user 'ga'
cat > /tmp/launch_ot.sh << EOF
#!/bin/bash
export DISPLAY=:1
# Try snap bin or system bin
if [ -x /snap/bin/opentoonz ]; then
    /snap/bin/opentoonz "$SCENE_PATH"
elif command -v opentoonz &> /dev/null; then
    opentoonz "$SCENE_PATH"
else
    echo "OpenToonz executable not found"
    exit 1
fi
EOF
chmod +x /tmp/launch_ot.sh

# Launch in background
su - ga -c "/tmp/launch_ot.sh" > /tmp/ot_launch.log 2>&1 &

# 4. Wait for Application
echo "Waiting for OpenToonz window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "OpenToonz detected."
        break
    fi
    sleep 1
done

# 5. Configure Window
sleep 5 # Wait for scene load
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss common startup popups if they appear
for i in {1..5}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 6. Capture Initial State Evidence
echo "Capturing initial screenshot..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="