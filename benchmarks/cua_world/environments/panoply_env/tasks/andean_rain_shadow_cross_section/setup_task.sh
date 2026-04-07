#!/bin/bash
echo "=== Setting up andean_rain_shadow_cross_section task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="andean_rain_shadow_cross_section"
DATA_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/OrographicStudy"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "Precipitation data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory owned by ga
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/andean_cross_section.png"
rm -f "$OUTPUT_DIR/rain_shadow_report.txt"
rm -f /home/ga/Desktop/rain_shadow_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis request to the desktop
cat > /home/ga/Desktop/rain_shadow_request.txt << 'SPECEOF'
DEPARTMENT OF PHYSICAL GEOGRAPHY — LECTURE PREP REQUEST
=======================================================
Request: ATSC-201 Orographic Precipitation Module
Role: Teaching Assistant / Lecturer

BACKGROUND
----------
The upcoming lecture requires a clear quantitative and visual demonstration of
the "Rain Shadow" effect caused by the Andes mountains. We need to show how
the easterly trade winds drop massive rainfall on the windward (Amazonian)
slope while leaving the leeward (Atacama) slope completely dry.

A standard 2D map is insufficient. We need a 1D spatial cross-section (a line
plot) that displays Longitude on the X-axis and Precipitation on the Y-axis.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Long-Term Mean Precipitation
  File: ~/PanoplyData/prate.sfc.mon.ltm.nc
  Variable: prate (Precipitation Rate, kg/m²/s)
- Tool: NASA Panoply

ANALYSIS PROCEDURE
------------------
1. Open the dataset in Panoply and select the 'prate' variable.
2. Create a 1D Line Plot (NOT a 2D geo-referenced map).
3. Configure the axes:
   - Horizontal axis MUST be Longitude.
   - Fix Time to January (the wet season).
   - Fix Latitude to the grid point closest to 15°S (15 degrees South).
4. Export the resulting cross-section plot showing the massive precipitation
   spike over the continent and the drop-off to the west.
5. Identify the approximate longitudes of the windward precipitation peak and
   the leeward (dry) minimum from the plot or array data.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/OrographicStudy/

1. 1D Cross-Section Plot:
   Filename: andean_cross_section.png
   (Export via File > Save Image As in the Panoply plot window)

2. Rain Shadow Report:
   Filename: rain_shadow_report.txt
   Required fields (use EXACTLY these key names, one per line):
     STUDY_REGION: South America
     LATITUDE_SLICE: 15S
     PEAK_WINDWARD_PRECIP_LON: [Insert longitude of max precip, e.g., 65W or 295E]
     MIN_LEEWARD_PRECIP_LON: [Insert longitude of the dry desert minimum to the west, e.g., 75W or 285E]
     METEOROLOGICAL_EFFECT: Rain Shadow

*Note on Coordinates:* Panoply may display longitudes in a 0-360E format.
Either standard (e.g., 65W) or 360-degree (e.g., 295E) formats are acceptable.
SPECEOF

chown ga:ga /home/ga/Desktop/rain_shadow_request.txt
chmod 644 /home/ga/Desktop/rain_shadow_request.txt
echo "Lecture request written to ~/Desktop/rain_shadow_request.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with precipitation data pre-loaded
echo "Launching Panoply with precipitation data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

focus_panoply
sleep 1

# Take initial screenshot showing Panoply open with dataset
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="