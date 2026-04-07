#!/bin/bash
echo "=== Setting up create_title_card_text task ==="

# Define paths
SOURCE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/title_card"

# 1. Prepare Output Directory
# Ensure it exists and is empty to prevent false positives from previous runs
if [ -d "$OUTPUT_DIR" ]; then
    echo "Cleaning existing output directory..."
    rm -f "$OUTPUT_DIR"/*
else
    echo "Creating output directory..."
    su - ga -c "mkdir -p $OUTPUT_DIR"
fi

# 2. Verify Source Scene
if [ ! -f "$SOURCE_SCENE" ]; then
    echo "ERROR: Source scene not found at $SOURCE_SCENE"
    # Attempt to use alternative if sample location differs
    ALT_SCENE=$(find /home/ga/OpenToonz -name "dwanko_run.tnz" | head -n 1)
    if [ -n "$ALT_SCENE" ]; then
        echo "Found scene at $ALT_SCENE, using that."
        SOURCE_SCENE="$ALT_SCENE"
    else
        echo "CRITICAL: Could not find dwanko_run.tnz"
        exit 1
    fi
fi

# 3. Record Initial State
# Count files in output dir (should be 0)
INITIAL_COUNT=$(find "$OUTPUT_DIR" -type f | wc -l)
echo "$INITIAL_COUNT" > /tmp/initial_file_count.txt

# Record start timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 4. Launch Application
echo "Launching OpenToonz..."
# Close any existing instances
pkill -f opentoonz 2>/dev/null || true
sleep 2

# Launch with the scene file loaded
# We use a wrapper to ensure it runs as user 'ga' and on the correct display
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

su - ga -c "/tmp/launch_ot.sh" &

# 5. Wait for Window and Configure
echo "Waiting for OpenToonz window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "Window detected."
        break
    fi
    sleep 1
done
sleep 5 # Allow scene to load

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss popup dialogs (Startup/Info)
# Press Escape a few times
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="