#!/bin/bash
set -e
echo "=== Setting up atmosphere_toggle_comparison task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Create output directory
OUTPUT_DIR="/home/ga/Documents"
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean any previous task artifacts
rm -f "$OUTPUT_DIR/everest_with_atmosphere.png" 2>/dev/null || true
rm -f "$OUTPUT_DIR/everest_without_atmosphere.png" 2>/dev/null || true
echo "Cleaned previous output files"

# Record initial state - no output files should exist
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "output_dir": "$OUTPUT_DIR",
    "file1_exists_initially": false,
    "file2_exists_initially": false,
    "atmosphere_default": "enabled"
}
EOF

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_task.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth Pro window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected at attempt $i"
        break
    fi
    sleep 1
done

# Additional wait for full initialization (globe loading)
sleep 5

# Get window ID
GE_WINDOW=$(wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
echo "Google Earth window ID: $GE_WINDOW"

# Maximize and focus Google Earth window
wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs by pressing Escape a few times
xdotool key Escape 2>/dev/null || true
sleep 0.5
xdotool key Escape 2>/dev/null || true
sleep 0.5

# Verify window is ready
FINAL_WINDOW=$(wmctrl -l | grep -i "Google Earth" | head -1)
echo "Final window state: $FINAL_WINDOW"

# Take screenshot of initial state for evidence
sleep 2
scrot /tmp/task_initial_state.png 2>/dev/null || true

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
echo "TASK: Create atmosphere comparison screenshots"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Search for 'Mount Everest' or navigate to coordinates 27.9881, 86.9250"
echo "2. Adjust view to ~50km altitude to see the peak and terrain"
echo "3. Save screenshot WITH atmosphere to:"
echo "   /home/ga/Documents/everest_with_atmosphere.png"
echo "4. Go to View menu > Atmosphere (uncheck to disable)"
echo "5. Save screenshot WITHOUT atmosphere to:"
echo "   /home/ga/Documents/everest_without_atmosphere.png"
echo ""
echo "Output directory: $OUTPUT_DIR"
echo "============================================================"