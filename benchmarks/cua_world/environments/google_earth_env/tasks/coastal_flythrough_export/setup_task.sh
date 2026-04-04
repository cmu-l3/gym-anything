#!/bin/bash
set -e
echo "=== Setting up Amalfi Coast Flythrough Export task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Create output directory and ensure it's clean
mkdir -p /home/ga/Videos
chown ga:ga /home/ga/Videos

# Remove any existing output file to ensure clean state
rm -f /home/ga/Videos/amalfi_flythrough.mp4
rm -f /home/ga/Videos/*.mp4 2>/dev/null || true

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "output_existed_before": false,
    "videos_dir_contents": "$(ls -la /home/ga/Videos/ 2>/dev/null | wc -l)"
}
EOF

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_flythrough.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..45}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after $i seconds"
        break
    fi
    if [ $i -eq 45 ]; then
        echo "WARNING: Google Earth window not detected after 45 seconds"
    fi
    sleep 1
done

# Get window ID
GE_WINDOW=$(wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
echo "Google Earth window ID: $GE_WINDOW"

# Maximize and focus the window
if [ -n "$GE_WINDOW" ]; then
    wmctrl -i -r "$GE_WINDOW" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    wmctrl -i -a "$GE_WINDOW" 2>/dev/null || true
    sleep 1
fi

# Dismiss any startup dialogs or tips by pressing Escape
xdotool key Escape 2>/dev/null || true
sleep 1
xdotool key Escape 2>/dev/null || true
sleep 1

# Create evidence directory
mkdir -p /tmp/task_evidence
chmod 777 /tmp/task_evidence

# Take initial screenshot
scrot /tmp/task_evidence/initial_state.png 2>/dev/null || \
    import -window root /tmp/task_evidence/initial_state.png 2>/dev/null || true

if [ -f /tmp/task_evidence/initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_evidence/initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Create Amalfi Coast Flythrough Video"
echo "============================================================"
echo ""
echo "You need to:"
echo "1. Navigate to the Amalfi Coast, Italy"
echo "   (Search for 'Amalfi Coast' or coordinates 40.6333, 14.6000)"
echo ""
echo "2. Create a path along the coastline (Add > Path)"
echo "   - Make the path at least 3 km long"
echo "   - Follow the cliffs between Positano and Amalfi"
echo ""
echo "3. Use Movie Maker (Tools > Movie Maker) to record a flythrough"
echo "   - Set resolution to 1280x720 (720p)"
echo "   - Duration approximately 15 seconds"
echo ""
echo "4. Save the video to: /home/ga/Videos/amalfi_flythrough.mp4"
echo ""
echo "============================================================"