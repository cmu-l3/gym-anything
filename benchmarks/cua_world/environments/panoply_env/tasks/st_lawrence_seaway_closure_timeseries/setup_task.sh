#!/bin/bash
echo "=== Setting up st_lawrence_seaway_closure_timeseries task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="st_lawrence_seaway_closure_timeseries"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/Seaway"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "Air temperature data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/st_lawrence_temp_series.png"
rm -f "$OUTPUT_DIR/shipping_season_report.txt"
rm -f /home/ga/Desktop/seaway_closure_mandate.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp (anti-gaming)
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/seaway_closure_mandate.txt << 'SPECEOF'
ST. LAWRENCE SEAWAY MANAGEMENT CORPORATION
MARITIME OPERATIONS DIVISION
=============================================================
SUBJECT: Winter Shipping Closure Assessment
LOCATION: St. Lawrence Seaway (Approx 45°N, 75°W)

The St. Lawrence Seaway is a vital shipping corridor connecting the Great Lakes to the Atlantic Ocean. Due to severe ice accumulation, the seaway must close during the winter months. We need to validate our standard closure schedule using long-term climatological air temperature data.

Ice formation rapidly accelerates when the mean monthly air temperature drops below freezing (0°C or 273.15 K).

YOUR TASKS:
1. Open the long-term mean air temperature dataset (air.mon.ltm.nc).
2. Extract a 1D time-series line plot showing the 12-month temperature cycle for the seaway chokepoint at Latitude 45°N, Longitude 75°W.
   *(Note: This dataset uses a 0-360° longitude grid. You must convert 75°W appropriately).*
3. Export this 1D plot as a PNG image to: ~/Documents/Seaway/st_lawrence_temp_series.png
4. Provide a text report identifying the specific months where the mean temperature is below freezing, and determine the coldest overall month. Save to: ~/Documents/Seaway/shipping_season_report.txt

REPORT FORMAT REQUIRED:
ANALYSIS_COORDINATES: [Latitude, Longitude used]
COLDEST_MONTH: [Month name]
SUB_FREEZING_MONTHS: [Comma-separated list of months below 0°C / 273.15K]
SAFE_SHIPPING_SEASON: [Comma-separated list of months above freezing]
SPECEOF

chown ga:ga /home/ga/Desktop/seaway_closure_mandate.txt
chmod 644 /home/ga/Desktop/seaway_closure_mandate.txt
echo "Mandate written to ~/Desktop/seaway_closure_mandate.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with air temperature data pre-loaded
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "panoply"; then
        echo "Panoply window detected"
        break
    fi
    sleep 2
done

# Let Panoply fully load
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Focus the Sources window
DISPLAY=:1 wmctrl -a "Panoply" 2>/dev/null || true
sleep 1

# Capture initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="