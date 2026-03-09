#!/bin/bash
echo "=== Setting up layer_visibility_infrastructure task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean any previous task artifacts
rm -f /home/ga/Documents/sf_infrastructure.png 2>/dev/null || true

# Ensure Documents directory exists with correct permissions
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
chmod 755 /home/ga/Documents

# Record initial state - check if output already exists
OUTPUT_PATH="/home/ga/Documents/sf_infrastructure.png"
if [ -f "$OUTPUT_PATH" ]; then
    INITIAL_EXISTS="true"
    INITIAL_SIZE=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c%Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
else
    INITIAL_EXISTS="false"
    INITIAL_SIZE="0"
    INITIAL_MTIME="0"
fi

# Save initial state for verification comparison
cat > /tmp/initial_state.json << EOF
{
    "output_exists": $INITIAL_EXISTS,
    "output_size": $INITIAL_SIZE,
    "output_mtime": $INITIAL_MTIME,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF
echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
echo "Stopping any existing Google Earth processes..."
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup su - ga -c "DISPLAY=:1 google-earth-pro" > /home/ga/google_earth.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Check if Google Earth started
if ! DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
    echo "WARNING: Google Earth window not detected after 60 seconds"
fi

# Maximize the window
echo "Maximizing Google Earth window..."
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the Google Earth window
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs/tips by pressing Escape
echo "Dismissing startup dialogs..."
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial screenshot for evidence
echo "Capturing initial state screenshot..."
sleep 2
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
echo "TASK: Infrastructure Layer Analysis - San Francisco"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Search for 'San Francisco, California' and navigate there"
echo "2. Open the Layers panel (sidebar on left)"
echo "3. Enable '3D Buildings' layer"
echo "4. Enable 'Roads' layer"  
echo "5. DISABLE 'Borders and Labels' layer"
echo "6. DISABLE 'Places' layer"
echo "7. Tilt the view to show 3D perspective"
echo "8. Save screenshot to: ~/Documents/sf_infrastructure.png"
echo ""
echo "Save using: File > Save > Save Image (or Ctrl+Alt+S)"
echo "============================================================"