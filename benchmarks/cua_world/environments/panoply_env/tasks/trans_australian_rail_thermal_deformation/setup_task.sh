#!/bin/bash
echo "=== Setting up trans_australian_rail_thermal_deformation task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="trans_australian_rail_thermal_deformation"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/RailRisk"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $DATA_FILE"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs
rm -f "$OUTPUT_DIR/australia_jan_heat.png"
rm -f "$OUTPUT_DIR/australia_jul_cold.png"
rm -f "$OUTPUT_DIR/thermal_buckling_report.txt"
rm -f /home/ga/Desktop/railway_engineering_mandate.txt

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"

# Write mandate
cat > /home/ga/Desktop/railway_engineering_mandate.txt << 'SPECEOF'
TRANS-AUSTRALIAN RAILWAY (CWR)
THERMAL DEFORMATION RISK ASSESSMENT
==================================================
Project: Nullarbor Plain Track Tensioning Baseline
Role: Civil Railway Engineer

BACKGROUND
----------
Continuous Welded Rail (CWR) networks lack expansion joints. They are laid at a
Stress-Free Temperature. If summer temperatures wildly exceed this baseline, the
track buckles ("sun kink"). If winter temperatures drop too low, it undergoes
tensile fracture. We need a climatological baseline of air temperatures to compute
the seasonal thermal amplitude for the Australian interior.

DATA REQUIREMENTS
-----------------
Dataset: NCEP/NCAR Surface Air Temperature Climatology
File: ~/PanoplyData/air.mon.ltm.nc
Variable: air (Monthly Long-Term Mean Air Temperature)
Time steps: January (Austral summer) and July (Austral winter)
Tool: NASA Panoply

REQUIRED ANALYSIS
-----------------
1. Map Centering: Create geo-mapped plots for January and July. Center the map
   projection on Australia (approx. Latitude -25, Longitude 135) and frame the continent.
2. Scale Standardization: You MUST override the default "Always fit to data" color limits
   in the Panoply "Scale" tab to standardize the maps.
   - For January: Set Scale Min to 290 and Max to 310
   - For July: Set Scale Min to 270 and Max to 290
3. Extract the peak mean temperature for January and minimum mean temperature
   for July in the central Australian interior.
4. Compute the THERMAL_AMPLITUDE_K (January peak minus July minimum).

DELIVERABLES
------------
Save all outputs to: ~/Documents/RailRisk/

1. January Heat Map: australia_jan_heat.png
2. July Cold Map: australia_jul_cold.png
3. Engineering Report: thermal_buckling_report.txt
   Required exact format (one per line):
   ASSESSMENT_REGION: Australia
   MAP_CENTER_LAT: [approx latitude, e.g., -25]
   MAP_CENTER_LON: [approx longitude, e.g., 135]
   JAN_PEAK_MEAN_K: [extracted value, e.g., 305.5]
   JUL_MIN_MEAN_K: [extracted value, e.g., 282.1]
   THERMAL_AMPLITUDE_K: [JAN_PEAK_MEAN_K minus JUL_MIN_MEAN_K]
   PRIMARY_SUMMER_RISK: Buckling
   PRIMARY_WINTER_RISK: Fracture
SPECEOF

chown ga:ga /home/ga/Desktop/railway_engineering_mandate.txt
chmod 644 /home/ga/Desktop/railway_engineering_mandate.txt

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with data pre-loaded
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

wait_for_panoply 90
sleep 10

DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

focus_panoply
sleep 1

# Open air variable
DISPLAY=:1 xdotool mousemove 728 530 click --repeat 2 --delay 100 1 2>/dev/null || true
sleep 3
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 8

# Take initial screenshot to prove starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="