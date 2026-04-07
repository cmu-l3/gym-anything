#!/bin/bash
echo "=== Setting up wind_ship_doldrums_routing task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="wind_ship_doldrums_routing"
DATA_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/SailRouting"
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

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/atlantic_slp_september.png"
rm -f "$OUTPUT_DIR/doldrums_crossing_report.txt"
rm -f /home/ga/Desktop/routing_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp (anti-gaming)
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the routing mandate to the desktop
cat > /home/ga/Desktop/routing_request.txt << 'SPECEOF'
NEO-WIND MARITIME LOGISTICS
METEOROLOGICAL ROUTING DIVISION — ANALYSIS MANDATE
===================================================
Voyage ID: NW-448 (Rotterdam to Rio de Janeiro)
Analyst Role: Meteorological Routing Analyst
Target Month: September

MANDATE OVERVIEW
----------------
Our wind-assisted hybrid cargo vessel is scheduled to cross the equatorial Atlantic 
Ocean this September. Wind-assisted vessels rely on the Trade Winds for propulsion
but are highly vulnerable to the "doldrums"—the Intertropical Convergence Zone (ITCZ).
The doldrums are characterized by a deep sea-level pressure trough, resulting in
calm, erratic winds that severely reduce our transit speed.

To optimize our track and minimize engine fuel consumption, we need to know the
climatological latitude and intensity of this pressure trough during September.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Long-Term Mean Sea Level Pressure
  File: ~/PanoplyData/slp.mon.ltm.nc
  Variable: slp (Sea Level Pressure, millibars/hPa)
  Target Time: September
- Tool: NASA Panoply

REQUIRED ANALYSIS
-----------------
1. Launch NASA Panoply and open the SLP climatology dataset.
2. Create a geo-mapped plot of the 'slp' variable.
3. Navigate to the September time step.
4. Zoom in on the equatorial Atlantic Ocean (approx. 20°S to 20°N, 50°W to 0°).
5. Identify the axis of minimum pressure (the doldrums trough).
6. Export the regional map and prepare the crossing report.

REQUIRED DELIVERABLES
----------------------
All outputs must be placed in: ~/Documents/SailRouting/

1. Atlantic SLP plot (September):
   Filename: atlantic_slp_september.png
   (Export via File > Save Image As in the Panoply plot window)

2. Doldrums crossing report:
   Filename: doldrums_crossing_report.txt
   Required fields (use EXACTLY these key names, one per line):
     ANALYSIS_MONTH: September
     OCEAN_BASIN: Atlantic
     DOLDRUMS_LATITUDE_N: [approximate latitude of the lowest pressure axis in degrees North]
     MIN_EQUATORIAL_SLP_HPA: [the minimum pressure value in the trough, in hPa]
     METEOROLOGICAL_EQUATOR_OFFSET: [North or South — relative to the geographic equator]

ANALYST NOTES
-------------
- The geographic equator is 0° latitude. The meteorological equator (doldrums) shifts 
  seasonally. You must determine its exact September position from the data.
- SLP is provided in millibars (mb), which are numerically identical to hectopascals (hPa).
SPECEOF

chown ga:ga /home/ga/Desktop/routing_request.txt
chmod 644 /home/ga/Desktop/routing_request.txt
echo "Routing request mandate written to ~/Desktop/routing_request.txt"

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

# Maximize Panoply
maximize_panoply 2>/dev/null || true
sleep 2

echo "Capturing initial state screenshot..."
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="