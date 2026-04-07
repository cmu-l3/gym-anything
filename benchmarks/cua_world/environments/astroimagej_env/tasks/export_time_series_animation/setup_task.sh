#!/bin/bash
echo "=== Setting up Time-Series Animation Export Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming (file creation check)
date +%s > /tmp/task_start_time.txt

# Create working directory
SERIES_DIR="/home/ga/AstroImages/time_series"
rm -rf "$SERIES_DIR"
mkdir -p "$SERIES_DIR"

# Ensure no old output exists
rm -f /home/ga/AstroImages/tracking_video.avi 2>/dev/null || true

# Check for cached WASP-12b dataset
WASP12_CACHE="/opt/fits_samples/WASP-12b_calibrated.tar.gz"

if [ ! -f "$WASP12_CACHE" ]; then
    echo "ERROR: WASP-12b cached data not found. Task environment is incomplete."
    exit 1
fi

echo "Extracting 30 frames from real WASP-12b data..."
# Extract to a temp directory first
mkdir -p /tmp/wasp12b_extract
tar -xzf "$WASP12_CACHE" -C /tmp/wasp12b_extract

# Pick the first 30 FITS files and move them to the target directory with sequential names
find /tmp/wasp12b_extract -type f \( -name "*.fits" -o -name "*.fit" \) | sort | head -n 30 > /tmp/wasp12b_files.txt

COUNT=1
while IFS= read -r file; do
    PADDED_COUNT=$(printf "%03d" $COUNT)
    mv "$file" "$SERIES_DIR/frame_${PADDED_COUNT}.fits"
    COUNT=$((COUNT + 1))
done < /tmp/wasp12b_files.txt

rm -rf /tmp/wasp12b_extract /tmp/wasp12b_files.txt
chown -R ga:ga "$SERIES_DIR"

# Launch AstroImageJ to give the agent a clean starting slate
echo "Launching AstroImageJ..."
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

su - ga -c "DISPLAY=:1 /usr/local/bin/aij > /tmp/astroimagej_ga.log 2>&1" &

# Wait for window and maximize
for i in {1..30}; do
    WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "ImageJ\|AstroImageJ" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        echo "AstroImageJ window detected ($WID)"
        DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -i -a "$WID" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot to record starting state
sleep 2
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Task Setup Complete ==="
echo "30 FITS files prepared in $SERIES_DIR"