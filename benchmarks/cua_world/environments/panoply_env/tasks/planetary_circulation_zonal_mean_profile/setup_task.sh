#!/bin/bash
echo "=== Setting up planetary_circulation_zonal_mean_profile task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="planetary_circulation_zonal_mean_profile"
DATA_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/ZonalCirculation"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: SLP data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "SLP data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/zonal_slp_annual.png"
rm -f "$OUTPUT_DIR/zonal_slp_annual.csv"
rm -f "$OUTPUT_DIR/pressure_belts_report.txt"
rm -f /home/ga/Desktop/circulation_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis brief to the desktop
cat > /home/ga/Desktop/circulation_brief.txt << 'SPECEOF'
UCAR EDUCATIONAL RESOURCES — PLANETARY CIRCULATION DIAGNOSTIC
=============================================================
Request ID: UCAR-2024-CIRC-01
Analyst: Climatology Content Developer
Priority: ROUTINE — Textbook update

BACKGROUND
----------
We are creating a new textbook infographic illustrating Earth's global pressure belts
(the Hadley, Ferrel, and Polar cells). To ensure scientific accuracy, we need the
pure, climatological baseline (annual, zonally-averaged) sea-level pressure profile
from 90°S to 90°N.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Long-Term Mean Sea Level Pressure
  File: ~/PanoplyData/slp.mon.ltm.nc
  Variable: slp (Sea Level Pressure, Pascals)
- Tool: NASA Panoply

ANALYSIS PROCEDURE
------------------
You must extract a 1D Zonal Mean profile of Sea Level Pressure:
1. Create a Line Plot along the Latitude axis for the 'slp' variable.
2. In the Array(s) tab, set the Longitude dimension to "Average" (to compute the zonal mean).
3. Set the Time dimension to "Average" (to compute the annual mean).
This filters out local weather and seasonal variations to reveal the planetary circulation.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/ZonalCirculation/

1. Zonal Mean SLP Plot:
   Filename: zonal_slp_annual.png
   (Export the visualization via File > Save Image As)

2. Zonal Mean SLP Data Array:
   Filename: zonal_slp_annual.csv
   (Export the underlying 1D data array via File > Export Data -> As CSV)

3. Pressure Belts Report:
   Filename: pressure_belts_report.txt
   Analyze the data to find the approximate latitudes of the major pressure belts.
   Required fields (use EXACTLY these key names, one per line).
   Report latitudes in degrees (use negative numbers for Southern Hemisphere, e.g., -45 for 45°S):
     SH_SUBTROPICAL_HIGH_LAT: [latitude of the pressure peak in the Southern Hemisphere]
     NH_SUBTROPICAL_HIGH_LAT: [latitude of the pressure peak in the Northern Hemisphere]
     EQUATORIAL_TROUGH_LAT: [latitude of the pressure minimum near the equator]
SPECEOF

chown ga:ga /home/ga/Desktop/circulation_brief.txt
chmod 644 /home/ga/Desktop/circulation_brief.txt
echo "Brief written to ~/Desktop/circulation_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with SLP data pre-loaded
echo "Launching Panoply with SLP data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Sources window
focus_panoply
sleep 1

# Take initial state screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="