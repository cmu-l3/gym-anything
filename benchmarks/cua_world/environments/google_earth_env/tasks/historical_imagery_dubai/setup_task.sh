#!/bin/bash
echo "=== Setting up Historical Imagery Dubai task ==="

export DISPLAY=${DISPLAY:-:1}
export HOME=${HOME:-/home/ga}
export USER=${USER:-ga}

# Ensure X server access
xhost +local: 2>/dev/null || true

# Record task start time (CRITICAL for anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Clean up any previous task artifacts
rm -f /home/ga/Documents/palm_jumeirah_2002.jpg 2>/dev/null || true
rm -f /home/ga/Documents/palm_jumeirah*.jpg 2>/dev/null || true
rm -f /home/ga/Documents/palm_jumeirah*.png 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Ensure output directory exists with correct permissions
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents
chmod 755 /home/ga/Documents

# Record initial state - check if output file exists (should not after cleanup)
OUTPUT_PATH="/home/ga/Documents/palm_jumeirah_2002.jpg"
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

# Kill any existing Google Earth instance for clean start
pkill -f google-earth-pro 2>/dev/null || true
sleep 2

# Start Google Earth Pro
echo "Starting Google Earth Pro..."
nohup su - ga -c "DISPLAY=:1 google-earth-pro" > /home/ga/google_earth_startup.log 2>&1 &
sleep 8

# Wait for Google Earth window to appear
echo "Waiting for Google Earth window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Google Earth"; then
        echo "Google Earth window detected after ${i} seconds"
        break
    fi
    if [ $i -eq 60 ]; then
        echo "WARNING: Google Earth window not detected after 60 seconds"
    fi
    sleep 1
done

# Additional wait for full application load
sleep 5

# Maximize window for better agent visibility
DISPLAY=:1 wmctrl -r "Google Earth" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Focus the window
DISPLAY=:1 wmctrl -a "Google Earth" 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs/tips by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Record Google Earth process info
GE_PID=$(pgrep -f google-earth-pro | head -1 || echo "0")
echo "Google Earth PID: $GE_PID"

# Take screenshot of initial state (for evidence and debugging)
mkdir -p /tmp/task_evidence
DISPLAY=:1 scrot /tmp/task_evidence/initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_evidence/initial_state.png 2>/dev/null || true

if [ -f /tmp/task_evidence/initial_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_evidence/initial_state.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo ""
echo "=== Task setup complete ==="
echo ""
echo "============================================================"
echo "TASK: Compare Historical Satellite Imagery of Dubai"
echo "============================================================"
echo ""
echo "Goal: View Palm Jumeirah area BEFORE the artificial islands"
echo "      were constructed (2002 or earlier)"
echo ""
echo "Steps:"
echo "1. Navigate to Palm Jumeirah, Dubai"
echo "   - Use Search (Ctrl+F) or click search box"
echo "   - Enter: Palm Jumeirah, Dubai, UAE"
echo "   - Or enter coordinates: 25.1124, 55.1390"
echo ""
echo "2. Enable Historical Imagery"
echo "   - Click the clock icon in toolbar, OR"
echo "   - View menu > Historical Imagery"
echo ""
echo "3. Use the time slider to select year 2002 or earlier"
echo "   - Drag slider left to go back in time"
echo "   - Look for imagery showing just coastline (no palm islands)"
echo ""
echo "4. Save screenshot"
echo "   - File > Save > Save Image, OR"
echo "   - Press Ctrl+Alt+S"
echo "   - Save to: /home/ga/Documents/palm_jumeirah_2002.jpg"
echo ""
echo "============================================================"