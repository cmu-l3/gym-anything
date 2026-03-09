#!/bin/bash
echo "=== Setting up change_map_projection task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi

echo "Data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
sleep 3

# Launch Panoply with the air temperature data file
echo "Launching Panoply with air temperature data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90

# Let Panoply fully load the file
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Panoply Sources window
focus_panoply
sleep 1

# The Sources window shows a variable list. The 'air' variable is in the list.
# We need to select 'air' and create a geo-mapped plot.
# In Panoply, the variable list is in the center of the Sources window.

# Take pre-plot screenshot
take_screenshot /tmp/task_before_plot.png

# Double-click on the 'air' variable to open the Create Plot dialog.
# For air.mon.ltm.nc, variable list: file_info, air, climatology_bounds, lat, lon, time, valid_yr_count
# The 'air' variable (type Geo2D) is the 2nd row at approximately (488, 313) in 1280x720.
# Scale to 1920x1080: (732, 470)
echo "Selecting 'air' variable..."
DISPLAY=:1 xdotool mousemove 732 470 click --repeat 2 --delay 100 1 2>/dev/null || true
sleep 3

# The Create Plot dialog should appear. Press Enter to create the default
# geo-referenced plot (Longitude-Latitude).
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 8

# Wait for the plot to render
echo "Waiting for plot to render..."
sleep 5

# Verify the correct variable was plotted
AIR_WINDOW=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep "air in air.mon.ltm" | head -1 | awk '{print $1}')
if [ -z "$AIR_WINDOW" ]; then
    echo "Warning: Air plot window not found. Attempting retry..."
    # Close any incorrectly created plot
    DISPLAY=:1 xdotool key ctrl+w 2>/dev/null || true
    sleep 2
    # Focus Sources window and try clicking each row
    DISPLAY=:1 wmctrl -a "Sources" 2>/dev/null || true
    sleep 1
    for vy in 301 314 327 340 353 365 378; do
        actual_vy=$((vy * 1080 / 720))
        DISPLAY=:1 xdotool mousemove 732 $actual_vy click --repeat 2 --delay 100 1 2>/dev/null || true
        sleep 2
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 5
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -q "air in air.mon.ltm"; then
            echo "Found air plot at row y=$vy"
            break
        fi
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 1
    done
fi

# Focus the Plot Controls window and switch to Map Projection view
DISPLAY=:1 wmctrl -a "Plot Controls" 2>/dev/null || true
sleep 1

# Click the "Show:" dropdown at approximately (120, 58) in 1280x720 -> (180, 87)
DISPLAY=:1 xdotool mousemove 180 87 click 1 2>/dev/null || true
sleep 1

# Select "Map Projection" at approximately (130, 111) in 1280x720 -> (195, 167)
DISPLAY=:1 xdotool mousemove 195 167 click 1 2>/dev/null || true
sleep 2

# Now the Plot Controls should show the projection dropdown with "Equirectangular"
# Focus the plot window to make it prominent
AIR_WINDOW=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep "air in air.mon.ltm" | head -1 | awk '{print $1}')
if [ -n "$AIR_WINDOW" ]; then
    DISPLAY=:1 wmctrl -i -a "$AIR_WINDOW" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
echo "Task: Change the map projection from Equirectangular to Orthographic"
echo "The air temperature plot is displayed with Equirectangular projection."
echo "Plot Controls shows Map Projection settings."
echo "Current windows:"
DISPLAY=:1 wmctrl -l 2>/dev/null || true
