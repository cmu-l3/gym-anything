#!/bin/bash
echo "=== Setting up Eagle Nebula Composite Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

WORK_DIR="/home/ga/AstroImages/eagle_nebula"
SOURCE_DIR="/opt/fits_samples/eagle_nebula"

# Clean up previous state
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
rm -f /tmp/task_start_time
rm -f /tmp/eagle_task_result.json

# Copy FITS files to working directory
echo "Copying FITS files to $WORK_DIR..."
if [ -d "$SOURCE_DIR" ]; then
    cp "$SOURCE_DIR"/502nmos.fits "$WORK_DIR/" 2>/dev/null || true
    cp "$SOURCE_DIR"/656nmos.fits "$WORK_DIR/" 2>/dev/null || true
    cp "$SOURCE_DIR"/673nmos.fits "$WORK_DIR/" 2>/dev/null || true
fi

# Fallback download if files are missing
for filter in 502nmos 656nmos 673nmos; do
    if [ ! -f "$WORK_DIR/${filter}.fits" ]; then
        echo "Warning: ${filter}.fits not found locally, downloading..."
        wget -q "https://esahubble.org/static/projects/fits_liberator/datasets/eagle/${filter}.zip" -O "/tmp/${filter}.zip"
        if [ -f "/tmp/${filter}.zip" ]; then
            unzip -o "/tmp/${filter}.zip" -d "$WORK_DIR/" 2>/dev/null
            rm "/tmp/${filter}.zip"
        fi
    fi
done

# Set permissions
chown -R ga:ga "$WORK_DIR"

# Launch AstroImageJ
echo "Launching AstroImageJ..."
if is_aij_running; then
    pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
    sleep 2
fi

export DISPLAY=:1
xhost +local: 2>/dev/null || true
su - ga -c "DISPLAY=:1 /home/ga/launch_astroimagej.sh > /tmp/aij_launch.log 2>&1" &

# Wait for application to start
sleep 5
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "ImageJ\|AstroImageJ"; then
        break
    fi
    sleep 1
done

# Maximize the main window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "ImageJ\|AstroImageJ" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Record start time for anti-gaming verification
date +%s > /tmp/task_start_time

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Task Setup Complete ==="