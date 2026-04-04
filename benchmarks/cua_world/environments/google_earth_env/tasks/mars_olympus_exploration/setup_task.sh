#!/bin/bash
set -e
echo "=== Setting up Mars Olympus Exploration task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean up any previous output files
OUTPUT_DIR="/home/ga/Documents"
mkdir -p "$OUTPUT_DIR"
rm -f "$OUTPUT_DIR/olympus_mons.png" 2>/dev/null || true
rm -f "$OUTPUT_DIR/olympus_mons.jpg" 2>/dev/null || true
rm -f "$OUTPUT_DIR/olympus_mons.jpeg" 2>/dev/null || true

# Set proper ownership
chown -R ga:ga "$OUTPUT_DIR"

# Record initial state - what files exist before task
echo "Recording initial state..."
ls -la "$OUTPUT_DIR" > /tmp/initial_output_dir.txt 2>/dev/null || echo "empty" > /tmp/initial_output_dir.txt

# Kill any existing Google Earth instances for clean start
echo "Cleaning up existing Google Earth instances..."
pkill -f "google-earth-pro" 2>/dev/null || true
pkill -f "googleearth" 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup su - ga -c "DISPLAY=:1 google-earth-pro" > /tmp/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth Pro window..."
WINDOW_FOUND=false
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        WINDOW_FOUND=true
        break
    fi
    sleep 1
done

if [ "$WINDOW_FOUND" = "false" ]; then
    echo "WARNING: Google Earth window not detected within timeout"
fi

# Additional wait for full initialization
sleep 5

# Maximize the Google Earth window
echo "Maximizing Google Earth window..."
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs or tips with Escape
echo "Dismissing any startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Record window state
echo "Recording window state..."
DISPLAY=:1 wmctrl -l > /tmp/initial_windows.txt 2>/dev/null || true

# Take screenshot of initial state (CRITICAL for verification)
echo "Capturing initial state screenshot..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

# Verify screenshot was captured
if [ -f /tmp/task_initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Navigate to Mars and capture Olympus Mons"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Switch to Mars view:"
echo "   - Go to View menu > Explore > Mars"
echo "   - OR click the planet icon in the toolbar"
echo ""
echo "2. Navigate to Olympus Mons:"
echo "   - Use the search bar (Ctrl+F or click search icon)"
echo "   - Search for 'Olympus Mons'"
echo "   - OR navigate to coordinates: 18.65°N, 226.2°E"
echo ""
echo "3. Save a screenshot:"
echo "   - Use File > Save > Save Image"
echo "   - Save to: /home/ga/Documents/olympus_mons.png"
echo ""
echo "Expected output: /home/ga/Documents/olympus_mons.png (or .jpg)"
echo "============================================================"