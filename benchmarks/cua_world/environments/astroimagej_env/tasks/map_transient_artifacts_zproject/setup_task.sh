#!/bin/bash
set -euo pipefail

echo "=== Setting up Map Transient Artifacts Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 2. Setup directories
TIME_SERIES_DIR="/home/ga/AstroImages/time_series"
ARTIFACTS_DIR="/home/ga/AstroImages/artifacts"

rm -rf "$TIME_SERIES_DIR" "$ARTIFACTS_DIR"
mkdir -p "$TIME_SERIES_DIR" "$ARTIFACTS_DIR"

# 3. Extract 30 real FITS frames from the WASP-12b dataset
CACHED_DATA="/opt/fits_samples/WASP-12b_calibrated.tar.gz"

if [ ! -f "$CACHED_DATA" ]; then
    echo "ERROR: Cached data not found at $CACHED_DATA"
    exit 1
fi

echo "Extracting 30 frames from WASP-12b dataset..."
mkdir -p /tmp/wasp12b_temp
tar -xzf "$CACHED_DATA" -C /tmp/wasp12b_temp

# Move exactly 30 frames to the target directory
find /tmp/wasp12b_temp -name "*.fits" | sort | head -n 30 | xargs -I {} mv {} "$TIME_SERIES_DIR/"
rm -rf /tmp/wasp12b_temp

# Fix permissions
chown -R ga:ga /home/ga/AstroImages

# 4. Launch AstroImageJ
echo "Launching AstroImageJ..."
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

AIJ_PATH=$(find /opt/astroimagej -name "AstroImageJ" -type f -executable | head -1)
if [ -z "$AIJ_PATH" ]; then
    AIJ_PATH="/usr/local/bin/aij"
fi

su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$AIJ_PATH' > /tmp/astroimagej_ga.log 2>&1 &"

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "ImageJ\|AstroImageJ"; then
        echo "AstroImageJ window detected"
        break
    fi
    sleep 1
done

# Maximize AIJ window
WID=$(get_aij_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="