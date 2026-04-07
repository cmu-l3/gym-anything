#!/bin/bash
echo "=== Setting up Time-Series Subframing Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create project directories
PROJECT_DIR="/home/ga/AstroImages/time_series"
RAW_DIR="$PROJECT_DIR/raw"
SUB_DIR="$PROJECT_DIR/subframes"

rm -rf "$PROJECT_DIR"
mkdir -p "$RAW_DIR" "$SUB_DIR"

# Extract exactly 20 real WASP-12b frames from cached tarball
WASP12_CACHE="/opt/fits_samples/WASP-12b_calibrated.tar.gz"

if [ ! -f "$WASP12_CACHE" ]; then
    echo "ERROR: WASP-12b data not found at $WASP12_CACHE"
    exit 1
fi

echo "Extracting 20 WASP-12b calibrated images..."
mkdir -p /tmp/wasp12b_temp
tar -xzf "$WASP12_CACHE" -C /tmp/wasp12b_temp 2>/dev/null || true

# Move first 20 FITS files to the raw directory
python3 << 'PYEOF'
import os, glob, shutil

src_dir = "/tmp/wasp12b_temp"
dst_dir = "/home/ga/AstroImages/time_series/raw"

fits_files = sorted(glob.glob(os.path.join(src_dir, "**/*.fits"), recursive=True) +
                    glob.glob(os.path.join(src_dir, "**/*.fit"), recursive=True))

for f in fits_files[:20]:
    shutil.move(f, os.path.join(dst_dir, os.path.basename(f)))
PYEOF

rm -rf /tmp/wasp12b_temp

# Set permissions
chown -R ga:ga "/home/ga/AstroImages"

# Provide instruction file as a hint
cat > "$PROJECT_DIR/instructions.txt" << 'EOF'
TARGET STAR INFO:
Look for the brightest star near X ≈ 1345, Y ≈ 2540 in the raw full-frame images.
You must crop all 20 frames to a 500x500 box around this star.

Remember to measure the sub-pixel centroid of this star in your NEW 500x500 subframes
(Frame 1 and Frame 20) and calculate the drift.
EOF
chown ga:ga "$PROJECT_DIR/instructions.txt"

# Ensure AstroImageJ is running
echo "Starting AstroImageJ..."
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' /usr/local/bin/aij > /tmp/astroimagej_ga.log 2>&1" &
sleep 10

# Maximize the AstroImageJ window
WID=$(DISPLAY=:1 wmctrl -l | grep -i "AstroImageJ" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Setup complete ==="