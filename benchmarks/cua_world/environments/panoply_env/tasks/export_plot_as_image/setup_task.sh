#!/bin/bash
echo "=== Setting up export_plot_as_image task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

DATA_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
EXPORT_DIR="/home/ga/Documents/PanoplyExports"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi

echo "Data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create export directory
mkdir -p "$EXPORT_DIR"
chown -R ga:ga "$EXPORT_DIR"

# Remove any existing export to ensure clean state
rm -f "$EXPORT_DIR/sst_plot.png"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
sleep 3

# Launch Panoply with the SST data file
echo "Launching Panoply with SST data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90

# Let Panoply fully load the file
sleep 10

# Dismiss any dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Panoply Sources window
focus_panoply
sleep 1

# The Sources window shows variables for sst.ltm.1991-2020.nc.
# Variable list order: file_info, climatology_bounds, lat, lon, sst, time, valid_yr_count
# The 'sst' variable (type Geo2D) is the 5th row at approximately (485, 353) in 1280x720.
# Scale to 1920x1080: (728, 530)
echo "Selecting 'sst' variable..."
DISPLAY=:1 xdotool mousemove 728 530 click --repeat 2 --delay 100 1 2>/dev/null || true
sleep 3

# Press Enter to create the default geo-referenced plot
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 8

# Wait for the plot to render
echo "Waiting for plot to render..."
sleep 5

# Verify the correct variable was plotted by checking window title
SST_WINDOW=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep "sst in sst" | head -1 | awk '{print $1}')
if [ -z "$SST_WINDOW" ]; then
    echo "Warning: SST plot window not found. Attempting retry..."
    # Close any incorrectly created plot
    DISPLAY=:1 xdotool key ctrl+w 2>/dev/null || true
    sleep 2
    # Focus Sources window and try clicking each row until we find sst
    DISPLAY=:1 wmctrl -a "Sources" 2>/dev/null || true
    sleep 1
    # Try rows from y=300 to y=400 (stepping by 13px in 1280x720 scale)
    for vy in 301 314 327 340 353 365 378; do
        actual_vy=$((vy * 1080 / 720))
        DISPLAY=:1 xdotool mousemove 728 $actual_vy click --repeat 2 --delay 100 1 2>/dev/null || true
        sleep 2
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 5
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -q "sst in sst"; then
            echo "Found SST plot at row y=$vy"
            break
        fi
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 1
    done
fi

# Focus the SST plot window
SST_WINDOW=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep "sst in sst" | head -1 | awk '{print $1}')
if [ -n "$SST_WINDOW" ]; then
    DISPLAY=:1 wmctrl -i -a "$SST_WINDOW" 2>/dev/null || true
    sleep 1
    echo "SST plot window focused: $SST_WINDOW"
else
    echo "Warning: Could not find SST plot window. Available windows:"
    DISPLAY=:1 wmctrl -l 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Export the SST plot as PNG to $EXPORT_DIR/sst_plot.png"
echo "Use File > Save Image As... (Ctrl+Shift+S) to export the plot."
echo "Export directory: $EXPORT_DIR"
echo "Current windows:"
DISPLAY=:1 wmctrl -l 2>/dev/null || true
