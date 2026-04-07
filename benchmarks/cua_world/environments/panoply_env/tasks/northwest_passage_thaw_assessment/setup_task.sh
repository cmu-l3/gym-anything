#!/bin/bash
echo "=== Setting up northwest_passage_thaw_assessment task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="northwest_passage_thaw_assessment"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/ArcticRouting"
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
rm -f "$OUTPUT_DIR/arctic_temp_july.png"
rm -f "$OUTPUT_DIR/arctic_temp_august.png"
rm -f "$OUTPUT_DIR/nwp_assessment.txt"
rm -f /home/ga/Desktop/arctic_routing_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis request to the desktop
cat > /home/ga/Desktop/arctic_routing_request.txt << 'SPECEOF'
GLOBAL MARITIME LOGISTICS CONSORTIUM
ARCTIC ROUTING FEASIBILITY REQUEST
===================================
Request ID: GMLC-NWP-2026-001
Analyst Role: Climate Analyst / Logistics Planner
Priority: HIGH

BACKGROUND
----------
We are evaluating the feasibility of sending a reinforced cargo vessel through
the Northwest Passage (Canadian Arctic Archipelago) during the summer melt
window. The route shaves thousands of miles off the Panama Canal route. To
model pack ice breakup, we need to know the climatological surface air
temperatures across the Arctic during July and August.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Surface Air Temperature (Long-Term Mean)
  File location: ~/PanoplyData/air.mon.ltm.nc
  Variable: air (Monthly Mean Air Temperature)
- Tool: NASA Panoply

IMPORTANT NOTE ON UNITS:
The NCEP 'air' dataset is provided in Kelvin (K). Standard Arctic summer
temperatures range from ~271K to ~283K. Our maritime engineering team
requires all temperature values reported in degrees Celsius (°C).
(Formula: °C = K - 273.15)

ANALYSIS INSTRUCTIONS
---------------------
1. Open the 'air' variable in Panoply as a geo-mapped plot.
2. Change the Map Projection from the default (Equirectangular) to a North
   Polar projection (e.g., North Polar Stereographic or North Polar Orthographic)
   so the Arctic Ocean and Canadian Archipelago are clearly visible in the center.
3. Export a plot for July (Month index 6) to the required output directory.
4. Export a plot for August (Month index 7) to the required output directory.
5. Visually estimate the approximate mean temperature over the Canadian Arctic
   Archipelago (approx. 70°N, 90°W) for both months, converting your estimates
   to Celsius.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/ArcticRouting/

1. July Polar Temperature Map:
   Filename: arctic_temp_july.png

2. August Polar Temperature Map:
   Filename: arctic_temp_august.png

3. Navigational Assessment Report:
   Filename: nwp_assessment.txt
   Required fields (use EXACTLY these key names, one per line):
     PROJECTION_USED: [Name of the Polar projection you applied in Panoply]
     JULY_TEMP_C: [Your estimated temperature in Celsius, e.g., 2.5]
     AUGUST_TEMP_C: [Your estimated temperature in Celsius, e.g., 3.1]
     REGION_ANALYZED: Canadian_Arctic_Archipelago

SUBMISSION: Please ensure the image files are clearly centered on the North Pole.
SPECEOF

chown ga:ga /home/ga/Desktop/arctic_routing_request.txt
chmod 644 /home/ga/Desktop/arctic_routing_request.txt
echo "Routing request spec file written to ~/Desktop/arctic_routing_request.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with Air Temp data pre-loaded
echo "Launching Panoply with Air Temp data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 60

# Let Panoply fully load
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus Panoply
focus_panoply
maximize_panoply

# Take an initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="