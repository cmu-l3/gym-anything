#!/bin/bash
set -euo pipefail

echo "=== Setting up tourism_4k_export task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Ensure output directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Remove any pre-existing output file to ensure clean state
if [ -f "/home/ga/Documents/bora_bora_4k.jpg" ]; then
    echo "Removing pre-existing output file..."
    rm -f /home/ga/Documents/bora_bora_4k.jpg
fi

# Record initial state
cat > /tmp/initial_state.json << EOF
{
    "output_exists": false,
    "task_start_time": $(cat /tmp/task_start_time.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF
echo "Initial state recorded:"
cat /tmp/initial_state.json

# Kill any existing Google Earth instances for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup sudo -u ga google-earth-pro > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth Pro window..."
for i in {1..60}; do
    if wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    sleep 1
done

# Additional wait for full application load
sleep 3

# Get window ID
WINDOW_ID=$(wmctrl -l | grep -i "Google Earth" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    echo "Window ID: $WINDOW_ID"
    
    # Maximize the window
    wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Focus the window
    wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    sleep 1
else
    echo "WARNING: Could not find Google Earth window ID"
    # Try generic approach
    wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    wmctrl -a "Google Earth" 2>/dev/null || true
fi

# Dismiss any startup dialogs or tips (press Escape a few times)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
echo "Capturing initial state screenshot..."
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

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
echo "TASK: Export a 4K tourism image of Bora Bora"
echo "============================================================"
echo ""
echo "Instructions:"
echo "1. Navigate to Bora Bora, French Polynesia"
echo "   (Search for 'Bora Bora, French Polynesia')"
echo ""
echo "2. Position view to show the lagoon and volcanic peaks"
echo ""
echo "3. Export image: File > Save > Save Image (or Ctrl+Alt+S)"
echo ""
echo "4. Settings in Save Image dialog:"
echo "   - Resolution: 3840 x 2160 (4K)"
echo "   - Title: Bora Bora Paradise"
echo "   - Enable scale legend"
echo ""
echo "5. Save to: /home/ga/Documents/bora_bora_4k.jpg"
echo "============================================================"