#!/bin/bash
echo "=== Setting up atacama_observatory_site_validation task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="atacama_observatory_site_validation"
PRES_FILE="/home/ga/PanoplyData/pres.mon.ltm.nc"
PRATE_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/Observatory"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data files exist
if [ ! -f "$PRES_FILE" ]; then
    echo "ERROR: Surface pressure data file not found: $PRES_FILE"
    exit 1
fi
if [ ! -f "$PRATE_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $PRATE_FILE"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs
rm -f "$OUTPUT_DIR/atacama_pres_jan.png"
rm -f "$OUTPUT_DIR/atacama_precip_jan.png"
rm -f "$OUTPUT_DIR/site_validation_report.txt"
rm -f /home/ga/Desktop/observatory_mandate.txt

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/observatory_mandate.txt << 'SPECEOF'
SPACE AGENCY SITE SELECTION COMMITTEE
CLIMATOLOGICAL VALIDATION MANDATE
======================================
Mandate ID: OBS-2026-VAL-09
Analyst Role: Site Selection Scientist
Target Site: Atacama Desert (Chajnantor Plateau region)

BACKGROUND
----------
We are evaluating a site in the Atacama Desert, Chile, for a new millimeter-wave
astronomical observatory. Such observations require extremely low column water
vapor, necessitating high altitude (low surface pressure) and hyper-arid conditions.
Before deploying weather-monitoring equipment, we must validate the baseline
climatology using standard NCEP global models for the month of January
(the peak of the Altiplanic winter, our most problematic season).

DATA REQUIREMENTS
-----------------
Dataset 1: NCEP Surface Pressure
File: ~/PanoplyData/pres.mon.ltm.nc
Variable: pres (Surface Pressure, Pascals)
Month: January (time index 0)

Dataset 2: NCEP Precipitation Rate
File: ~/PanoplyData/prate.sfc.mon.ltm.nc
Variable: prate (Precipitation Rate, kg/m^2/s)
Month: January (time index 0)

TARGET COORDINATES
------------------
Latitude: 22.5° S (-22.5)
Longitude: 67.5° W (-67.5)
Note: Panoply uses a 0-360 longitude system. 67.5°W corresponds to 292.5°E.

REQUIRED ANALYSIS
-----------------
Using NASA Panoply, you must:
1. Open the surface pressure dataset and create a geo-mapped plot for January.
2. Zoom the map to South America and export the plot.
3. Click on the map at the exact target coordinates to read the underlying data
   array value for Surface Pressure using Panoply's data inspector.
4. Open the precipitation rate dataset, create a geo-mapped plot for January,
   zoom to South America, and export the plot.
5. Read the underlying data array value for Precipitation Rate at the same coordinates.

IMPORTANT: Do not estimate the values from the color bar or use real-world
empirical data. You must extract the EXACT values reported by the NCEP model
for that specific grid cell in Panoply.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/Observatory/

1. Surface Pressure Map (January):
   Filename: atacama_pres_jan.png

2. Precipitation Rate Map (January):
   Filename: atacama_precip_jan.png

3. Site Validation Report:
   Filename: site_validation_report.txt
   Required fields (use EXACTLY these key names, one per line):
     SITE_NAME: Atacama_Chajnantor
     TARGET_LAT: -22.5
     TARGET_LON: -67.5
     JAN_SURFACE_PRESSURE_PA: [Extract the exact numeric value from Panoply, e.g., 73150.5]
     JAN_PRECIP_RATE: [Extract the exact numeric value from Panoply]
     EVALUATION_MONTH: January
SPECEOF

chown ga:ga /home/ga/Desktop/observatory_mandate.txt
chmod 644 /home/ga/Desktop/observatory_mandate.txt

# Launch Panoply
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh &"
wait_for_panoply 90
sleep 10
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
focus_panoply

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="