#!/bin/bash
echo "=== Setting up vendee_globe_southern_ocean_risk task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="vendee_globe_southern_ocean_risk"
DATA_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/VendeeGlobe"
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
rm -f "$OUTPUT_DIR/southern_ocean_slp_jan.png"
rm -f "$OUTPUT_DIR/route_advisory.txt"
rm -f /home/ga/Desktop/routing_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/routing_request.txt << 'SPECEOF'
VENDÉE GLOBE RACE MANAGEMENT
MARINE ROUTING WEATHER ADVISORY REQUEST
=======================================================
Request ID: VG-2024-JAN-SO-001
Analyst Role: Marine Routing Meteorologist
Sector: Southern Ocean (Indian Ocean Entry - 20°E)

BACKGROUND
----------
The fleet is approaching the Cape of Good Hope and preparing to enter the 
"Roaring Forties" and "Furious Fifties" of the Southern Ocean. The strength of 
these severe westerly winds is directly proportional to the meridional pressure 
gradient between the Subtropical High (approx 30°S) and the Antarctic 
Circumpolar Trough (approx 60°S).

We need a baseline climatological assessment of this pressure gradient for 
January (the austral summer race period) to calibrate our wind risk models.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Surface Sea Level Pressure
  File location: ~/PanoplyData/slp.mon.ltm.nc
  Variable: slp (Sea Level Pressure)
  Time step: January (index 0)
- Tool: NASA Panoply

REQUIRED ANALYSIS
-----------------
1. Map Projection: Create a geo-mapped plot of January SLP, but CHANGE the map 
   projection from the default Equirectangular to a South Polar projection 
   (e.g., South Polar Stereographic, Orthographic, or Azimuthal) to center 
   Antarctica and accurately display the Southern Ocean. Export this map.

2. Data Extraction: Use Panoply's Array view or precise cursor hover over the 
   plot to extract the EXACT Sea Level Pressure values for January at longitude 
   20°E (south of Africa) for two latitudes: 30°S and 60°S.
   
   *NOTE:* If the raw NCEP data displays in Pascals (e.g., 101500), you MUST 
   convert it to meteorological standard hectopascals (hPa/mb) by dividing by 100 
   (e.g., 1015 hPa) before writing the report.

3. Calculate Gradient: Calculate the pressure difference:
   Gradient = Pressure at 30°S - Pressure at 60°S

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/VendeeGlobe/

1. South Polar SLP map:
   Filename: southern_ocean_slp_jan.png

2. Route advisory report:
   Filename: route_advisory.txt
   Required fields (use EXACTLY these key names, one per line):
     ANALYSIS_MONTH: January
     PRESSURE_30S_20E_HPA: [extracted value converted to hPa, e.g. 1015]
     PRESSURE_60S_20E_HPA: [extracted value converted to hPa, e.g. 985]
     PRESSURE_GRADIENT_HPA: [calculated difference in hPa]

SUBMISSION DEADLINE: Immediate
SPECEOF

chown ga:ga /home/ga/Desktop/routing_request.txt
chmod 644 /home/ga/Desktop/routing_request.txt
echo "Routing request written to ~/Desktop/routing_request.txt"

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

# Pre-select the slp variable
DISPLAY=:1 xdotool mousemove 728 530 click --repeat 2 --delay 100 1 2>/dev/null || true
sleep 3
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 5

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="