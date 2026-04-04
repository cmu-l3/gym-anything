#!/bin/bash
set -e
echo "=== Setting up Macro Recording Task ==="

# 1. Define paths
OUTPUT_DIR="/home/ga/Fiji_Data/results/macros"
OUTPUT_FILE="$OUTPUT_DIR/clean_and_segment.ijm"

# 2. Record start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 3. Create output directory and clean previous artifacts
if [ ! -d "$OUTPUT_DIR" ]; then
    echo "Creating output directory: $OUTPUT_DIR"
    su - ga -c "mkdir -p '$OUTPUT_DIR'"
fi

# Remove the target file if it exists to ensure a fresh start
if [ -f "$OUTPUT_FILE" ]; then
    echo "Removing previous output file..."
    rm -f "$OUTPUT_FILE"
fi

# 4. Launch Fiji if not running
if ! pgrep -f "fiji" > /dev/null && ! pgrep -f "ImageJ" > /dev/null; then
    echo "Launching Fiji..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "Fiji\|ImageJ" > /dev/null; then
            echo "Fiji window detected."
            break
        fi
        sleep 1
    done
    sleep 5
else
    echo "Fiji is already running."
fi

# 5. Ensure window is maximized and focused
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

DISPLAY=:1 wmctrl -a "Fiji" 2>/dev/null || \
DISPLAY=:1 wmctrl -a "ImageJ" 2>/dev/null || true

# 6. Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="