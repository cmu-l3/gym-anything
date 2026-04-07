#!/bin/bash
set -e
echo "=== Setting up vectorize_lineart_asset task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Create directories
INPUT_DIR="/home/ga/OpenToonz/inputs"
OUTPUT_DIR="/home/ga/OpenToonz/outputs/vectorized"

su - ga -c "mkdir -p $INPUT_DIR"
su - ga -c "mkdir -p $OUTPUT_DIR"

# Clean previous outputs
rm -f "$OUTPUT_DIR/director_sketch.pli"
rm -f "$OUTPUT_DIR/director_sketch.png" # Prevent confusion if user saves as PNG

# Generate input data (Synthetic line art)
echo "Generating synthetic sketch..."
SKETCH_PATH="$INPUT_DIR/director_sketch.png"

# Create a white background with black lines using ImageMagick
# We draw a bezier curve and a circle to simulate a drawing
convert -size 800x600 xc:white \
    -fill none -stroke black -strokewidth 3 \
    -draw "path 'M 100,500 C 100,200 700,200 700,500'" \
    -draw "circle 400,300 350,250" \
    -draw "line 200,400 600,400" \
    "$SKETCH_PATH"

chown ga:ga "$SKETCH_PATH"
echo "Input generated at $SKETCH_PATH"

# Ensure OpenToonz is running
if ! pgrep -f "opentoonz" > /dev/null; then
    echo "Starting OpenToonz..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Dismiss any startup popups
for i in {1..3}; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="