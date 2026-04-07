#!/bin/bash
echo "=== Setting up apply_negative_filter_render task ==="

SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/negative_fx"

# 1. Clean previous state
echo "Cleaning output directory..."
su - ga -c "mkdir -p $OUTPUT_DIR"
rm -f "$OUTPUT_DIR"/*.png 2>/dev/null || true
rm -f "$OUTPUT_DIR"/*.tga 2>/dev/null || true

# 2. Verify Source Data
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Try to find it elsewhere or fail
    FOUND=$(find /home/ga/OpenToonz -name "dwanko_run.tnz" | head -1)
    if [ -n "$FOUND" ]; then
        SOURCE_SCENE="$FOUND"
        echo "Found at $SOURCE_SCENE"
    else
        echo "Critical: Sample data missing."
        exit 1
    fi
fi

# 3. Launch OpenToonz with the scene
echo "Launching OpenToonz..."
pkill -f opentoonz 2>/dev/null || true
sleep 2

# Create a launcher to ensure display var is set
cat > /tmp/launch_ot.sh << EOF
#!/bin/bash
export DISPLAY=:1
if [ -x /snap/bin/opentoonz ]; then
    /snap/bin/opentoonz "$SOURCE_SCENE"
elif command -v opentoonz &> /dev/null; then
    opentoonz "$SOURCE_SCENE"
else
    echo "OpenToonz executable not found"
    exit 1
fi
EOF
chmod +x /tmp/launch_ot.sh

su - ga -c "/tmp/launch_ot.sh &"

# Wait for window
echo "Waiting for OpenToonz to load..."
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "OpenToonz window detected."
        break
    fi
    sleep 1
done
sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss popup dialogs if any (startup popup)
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 4. Record Timestamp for Anti-Gaming
date +%s > /tmp/task_start_timestamp

# 5. Capture Initial State
sleep 2
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup Complete ==="