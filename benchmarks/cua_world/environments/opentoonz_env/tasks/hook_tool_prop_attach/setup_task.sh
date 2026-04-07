#!/bin/bash
echo "=== Setting up hook_tool_prop_attach task ==="

# Define paths
ASSETS_DIR="/home/ga/OpenToonz/assets"
PROJECT_DIR="/home/ga/OpenToonz/projects/spy_run"
SAMPLES_DIR="/home/ga/OpenToonz/samples"

# Ensure directories exist
su - ga -c "mkdir -p $ASSETS_DIR"
su - ga -c "mkdir -p $PROJECT_DIR"
su - ga -c "mkdir -p $SAMPLES_DIR"

# Clean up previous run
rm -f "$PROJECT_DIR/spy_run.tnz" 2>/dev/null || true
rm -f "$PROJECT_DIR/spy_run.mp4" 2>/dev/null || true
rm -f "$PROJECT_DIR/spy_run.xml" 2>/dev/null || true

# Generate the sunglasses prop (transparent PNG)
# Two black rounded rectangles connected by a bridge
echo "Generating sunglasses asset..."
convert -size 300x150 xc:transparent \
    -fill black -draw "roundrectangle 20,40 130,110 20,20" \
    -fill black -draw "roundrectangle 170,40 280,110 20,20" \
    -fill black -draw "rectangle 130,60 170,70" \
    -fill "#404040" -draw "roundrectangle 30,50 120,100 15,15" \
    -fill "#404040" -draw "roundrectangle 180,50 270,100 15,15" \
    "$ASSETS_DIR/sunglasses.png"

chown ga:ga "$ASSETS_DIR/sunglasses.png"

# Ensure sample scene exists (dwanko_run.tnz)
# If not present (e.g., failed download in env setup), try to fetch or warn
if [ ! -f "$SAMPLES_DIR/dwanko_run.tnz" ]; then
    echo "Warning: dwanko_run.tnz not found. Attempting download..."
    wget -q https://github.com/opentoonz/opentoonz_sample/raw/master/dwanko_run.tnz -O "$SAMPLES_DIR/dwanko_run.tnz" || echo "Download failed."
    # We assume the environment setup script handled the samples, 
    # but this is a fallback.
fi
chown ga:ga "$SAMPLES_DIR/dwanko_run.tnz" 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start OpenToonz
# We start it empty so the user has to open the file (as per task instructions)
echo "Starting OpenToonz..."
if ! pgrep -f "opentoonz" > /dev/null; then
    su - ga -c "DISPLAY=:1 /usr/local/bin/launch-opentoonz &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenToonz"; then
        echo "OpenToonz started."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "OpenToonz" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenToonz" 2>/dev/null || true

# Close startup popup if it appears
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="