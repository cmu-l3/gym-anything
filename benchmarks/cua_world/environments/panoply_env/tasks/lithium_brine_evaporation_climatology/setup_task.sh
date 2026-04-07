#!/bin/bash
echo "=== Setting up lithium_brine_evaporation_climatology task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="lithium_brine_evaporation_climatology"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/LithiumProspecting"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "Air temperature data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory owned by ga
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/tibet_temp_jan.png"
rm -f "$OUTPUT_DIR/andes_temp_jan.png"
rm -f "$OUTPUT_DIR/evaporation_feasibility.txt"
rm -f /home/ga/Desktop/lithium_prospecting_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the prospecting brief to the desktop
cat > /home/ga/Desktop/lithium_prospecting_brief.txt << 'SPECEOF'
LITHIUM PROSPECTING CLIMATOLOGY BRIEF
=====================================
Request ID: LITH-2024-JAN-091
Analyst Role: Climate Data Analyst
Focus: Tibetan Plateau vs. Andean Baseline

BACKGROUND
----------
Lithium is extracted from underground brine pumped into massive surface evaporation
ponds. This process requires continuous evaporation, which is highly dependent on
local climate conditions (high temperatures, strong solar radiation). We are
evaluating the feasibility of year-round lithium brine evaporation at Zabuye Salt
Lake on the Tibetan Plateau (~30°N, 85°E) against our established baseline at
Salar de Atacama in the Andes (~23°S, 68°W).

A critical risk for the Tibetan site is winter freezing, which halts evaporation.
You must analyze the January surface air temperature climatology for both regions.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Surface Monthly Long-Term Mean
  File location: ~/PanoplyData/air.mon.ltm.nc
  Variable: air (Air Temperature)
  Time step: January (Time index 0)
- Tool: NASA Panoply

IMPORTANT UNIT CONVERSIONS:
The NCEP 'air' dataset natively stores temperature in Kelvin (K).
You must convert the temperatures you extract into Celsius (°C) for the report.
Formula: °C = K - 273.15

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/LithiumProspecting/

1. Geo-mapped plot of January temperatures centered on the Tibetan Plateau:
   Filename: tibet_temp_jan.png
   (Adjust the map view to focus on the Asian/Tibetan region)

2. Geo-mapped plot of January temperatures centered on the Andes:
   Filename: andes_temp_jan.png
   (Adjust the map view to focus on the South American/Andean region)

3. Feasibility assessment report:
   Filename: evaporation_feasibility.txt
   Required fields (use EXACTLY these key names, one per line):
     TIBET_JAN_TEMP_C: [estimated mean January temp for the Tibetan Plateau in Celsius]
     ANDES_JAN_TEMP_C: [estimated mean January temp for the Atacama/Andes in Celsius]
     WINTER_EVAPORATION_FEASIBLE_TIBET: [YES or NO - based on whether the Tibetan brine will freeze (< 0°C)]
SPECEOF

chown ga:ga /home/ga/Desktop/lithium_prospecting_brief.txt
chmod 644 /home/ga/Desktop/lithium_prospecting_brief.txt
echo "Prospecting brief written to ~/Desktop/lithium_prospecting_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with data pre-loaded
echo "Launching Panoply with air temperature data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90

# Let Panoply fully load
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Panoply Sources window
focus_panoply
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
echo "Took initial screenshot at /tmp/task_initial.png"

echo "=== Setup Complete ==="