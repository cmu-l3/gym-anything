#!/bin/bash
echo "=== Setting up Alien Variant Palette Swap task ==="

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/alien_variant"

# 1. Clean up and prepare directories
# Ensure output directory exists and is empty to prevent false positives
su - ga -c "mkdir -p $OUTPUT_DIR"
find "$OUTPUT_DIR" -maxdepth 1 -name "*.png" -delete 2>/dev/null || true
find "$OUTPUT_DIR" -maxdepth 1 -name "*.tga" -delete 2>/dev/null || true
echo "Output directory cleared: $OUTPUT_DIR"

# 2. Verify source data exists
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Attempt to use backup if available or fail
    exit 1
fi

# 3. Record initial state
# Count existing files (should be 0)
INITIAL_COUNT=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.png" | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_file_count.txt

# Record task start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 4. Launch Application
# Start OpenToonz maximized to ensure the agent can see the palette window
echo "Starting OpenToonz..."
if ! pgrep -f "opentoonz" > /dev/null; then
    su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &" || su - ga -c "DISPLAY=:1 opentoonz &"
    
    # Wait for window to appear
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz window detected"
            break
        fi
        sleep 1
    done
    
    # Wait a bit longer for full initialization
    sleep 5
fi

# Maximize the window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss common startup dialogs if they appear
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# 5. Capture Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="