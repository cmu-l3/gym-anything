#!/bin/bash
set -e
echo "=== Setting up retime_animation_breakdown task ==="

# Define paths
SAMPLE_SCENE="/home/ga/OpenToonz/samples/dwanko_run.tnz"
OUTPUT_DIR="/home/ga/OpenToonz/output/retimed"
TIMING_CHART="/home/ga/Desktop/timing_chart.txt"

# 1. Clean previous state
echo "Cleaning output directory..."
rm -rf "$OUTPUT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# 2. Verify source scene exists
if [ ! -f "$SAMPLE_SCENE" ]; then
    echo "ERROR: Source scene $SAMPLE_SCENE not found!"
    # Try to find it if moved
    FOUND=$(find /home/ga -name "dwanko_run.tnz" | head -n 1)
    if [ -n "$FOUND" ]; then
        echo "Found scene at $FOUND, symlinking..."
        su - ga -c "ln -sf '$FOUND' '$SAMPLE_SCENE'"
    else
        echo "CRITICAL: Could not find dwanko_run.tnz"
        # We might need to download it or fail
        exit 1
    fi
fi

# 3. Create the Timing Chart file
echo "Creating timing chart..."
cat > "$TIMING_CHART" << 'EOF'
TIMING INSTRUCTIONS
Scene: dwanko_run
Total Duration: 24 frames

The director wants a "stop-and-go" rhythm. Please expose the drawings as follows:

Frame Range   | Drawing #  | Description
--------------|------------|---------------------
01 - 04       | 1          | Hold start pose
05 - 06       | 3          | Quick step (skip 2)
07 - 08       | 5          | Land (skip 4)
09 - 10       | 7          | Anticipate
11 - 20       | 9          | Long Hold / Pause
21 - 24       | 1          | Return to start

Instructions:
1. Open the Xsheet.
2. Adjust the frame exposures for Column 1 to match the table above.
3. Set the output range to frames 1-24.
4. Render as PNG to /home/ga/OpenToonz/output/retimed/
EOF

chown ga:ga "$TIMING_CHART"
chmod 644 "$TIMING_CHART"

# 4. Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. Launch OpenToonz (optional but helpful state)
# We ensure OT is running to save the agent startup time, 
# but we don't load the scene automatically to force the agent to File > Open
if ! pgrep -f "OpenToonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /snap/bin/opentoonz &" > /dev/null 2>&1 || \
    su - ga -c "DISPLAY=:1 opentoonz &" > /dev/null 2>&1 &
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            echo "OpenToonz started."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="