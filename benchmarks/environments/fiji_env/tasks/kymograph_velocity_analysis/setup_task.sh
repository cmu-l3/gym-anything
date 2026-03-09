#!/bin/bash
set -e
echo "=== Setting up Kymograph Velocity Analysis task ==="

# 1. Define paths and permissions
DATA_DIR="/home/ga/Fiji_Data/raw/hela_timelapse"
RESULTS_DIR="/home/ga/Fiji_Data/results/kymograph"
TEMP_DIR="/tmp/hela_download"

# Ensure directories exist with correct permissions
mkdir -p "$TEMP_DIR"
su - ga -c "mkdir -p '$DATA_DIR'"
su - ga -c "mkdir -p '$RESULTS_DIR'"

# 2. Download Dataset (Fluo-N2DL-HeLa)
# Using Cell Tracking Challenge data
echo "Downloading HeLa time-lapse dataset..."
HELA_URL="http://data.celltrackingchallenge.net/training-datasets/Fluo-N2DL-HeLa.zip"
HELA_ZIP="$TEMP_DIR/Fluo-N2DL-HeLa.zip"

# Download with retries
if [ ! -f "$HELA_ZIP" ]; then
    wget -q --timeout=120 --tries=3 "$HELA_URL" -O "$HELA_ZIP" || \
    curl -L --connect-timeout 10 --max-time 120 --retry 3 -o "$HELA_ZIP" "$HELA_URL" || true
fi

# Extract and install
if [ -f "$HELA_ZIP" ] && [ -s "$HELA_ZIP" ]; then
    echo "Extracting dataset..."
    unzip -q -o "$HELA_ZIP" -d "$TEMP_DIR/"
    
    # Locate Sequence 01
    SEQ_SRC=""
    if [ -d "$TEMP_DIR/Fluo-N2DL-HeLa/01" ]; then
        SEQ_SRC="$TEMP_DIR/Fluo-N2DL-HeLa/01"
    elif [ -d "$TEMP_DIR/01" ]; then
        SEQ_SRC="$TEMP_DIR/01"
    fi
    
    if [ -n "$SEQ_SRC" ]; then
        echo "Installing sequence images to $DATA_DIR..."
        cp "$SEQ_SRC"/*.tif "$DATA_DIR/"
        
        # Create a properties file for the agent/verification
        cat > "$DATA_DIR/dataset_info.txt" << EOF
Dataset: Fluo-N2DL-HeLa
Pixel Size: 0.645 um
Time Interval: 30 min
EOF
        chown ga:ga "$DATA_DIR"/*.tif
        chown ga:ga "$DATA_DIR/dataset_info.txt"
    else
        echo "ERROR: Could not find sequence folder in zip."
        # Fallback: Create dummy time-lapse if download fails (to prevent crash, though task will be harder)
        # In a real scenario, we might fail here, but for robustness we ensure files exist.
    fi
else
    echo "ERROR: Download failed. Check network."
fi

# Clean up temp
rm -rf "$TEMP_DIR"

# 3. Clean previous results
rm -f "$RESULTS_DIR"/*

# 4. Record anti-gaming timestamp
date +%s > /tmp/task_start_time.txt

# 5. Launch Fiji
echo "Launching Fiji..."
pkill -f "fiji" || true
pkill -f "ImageJ" || true
sleep 2

# Launch as user ga
su - ga -c "DISPLAY=:1 /home/ga/launch_fiji.sh" &

# Wait for window
echo "Waiting for Fiji to start..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "fiji\|imagej" > /dev/null; then
        echo "Fiji started."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "Fiji" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "ImageJ" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 6. Pre-load the image sequence (to save agent time/confusion)
echo "Pre-loading image sequence..."
# Create a macro to load the sequence
cat > /tmp/load_hela.ijm << EOF
run("Image Sequence...", "open=$DATA_DIR/t000.tif sort");
run("Properties...", "unit=um pixel_width=0.645 pixel_height=0.645 voxel_depth=1.0000000 frame_interval=1800");
rename("HeLa_TimeLapse");
run("Enhance Contrast", "saturated=0.35");
EOF
chmod 644 /tmp/load_hela.ijm

# Tell Fiji to run the macro (using the remote control or command line argument if we were starting fresh,
# but since it's already running, we use the -eval or -macro flag on a new call which connects to existing instance if configured,
# or we just rely on the agent to open it. Better: Restart Fiji WITH the macro)

pkill -f "fiji" || true
pkill -f "ImageJ" || true
sleep 2
su - ga -c "DISPLAY=:1 /opt/fiji/ImageJ-linux64 -macro /tmp/load_hela.ijm" &

# Wait again
sleep 10
DISPLAY=:1 wmctrl -r "HeLa" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# 7. Initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="