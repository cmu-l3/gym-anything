#!/bin/bash
echo "=== Setting up reanalysis_topographic_smoothing_assessment task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="reanalysis_topographic_smoothing_assessment"
TEMP_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
PRATE_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/AgriRisk"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify both data files exist
if [ ! -f "$TEMP_FILE" ]; then
    echo "ERROR: Temperature data file not found: $TEMP_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
if [ ! -f "$PRATE_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $PRATE_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "Temperature data: $TEMP_FILE ($(stat -c%s "$TEMP_FILE") bytes)"
echo "Precipitation data: $PRATE_FILE ($(stat -c%s "$PRATE_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/colombia_temp_annual.png"
rm -f "$OUTPUT_DIR/colombia_precip_annual.png"
rm -f "$OUTPUT_DIR/veto_memo.txt"
rm -f /home/ga/Desktop/insurance_model_mandate.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/insurance_model_mandate.txt << 'SPECEOF'
AGRI-RISK REINSURANCE CORP. — METHODOLOGICAL VETO MANDATE
==========================================================
Mandate ID: AGR-2024-COL-092
Analyst Role: Agricultural Risk Actuary
Subject: Rejecting NCEP 2.5-degree Climatology for Andean Coffee Insurance

MANDATE OVERVIEW
----------------
The automated underwriting system has proposed rejecting crop insurance
applications from the Colombian Coffee Axis (Eje Cafetero, specifically near
Manizales) because its baseline climate model shows the region is "too hot"
for Arabica coffee (which requires 18-22°C).

As the regional methodology actuary, you know the real-world temperature in
the high-altitude Andes is perfectly suited for coffee (~18°C). The automated
system is using coarse global reanalysis data (NCEP/NCAR at 2.5° resolution)
that suffers from severe topographic smoothing.

You must prove that the dataset is hallucinating a hot climate by extracting
the raw dataset values, plotting the annual profiles, and writing a veto memo
explaining the spatial resolution error.

DATA REQUIREMENTS
-----------------
- Dataset 1: NCEP/NCAR Reanalysis Surface Air Temperature
  File: ~/PanoplyData/air.mon.ltm.nc (Variable: air)
- Dataset 2: NCEP/NCAR Reanalysis Surface Precipitation Rate
  File: ~/PanoplyData/prate.sfc.mon.ltm.nc (Variable: prate)
- Tool: NASA Panoply

TARGET COORDINATES
------------------
Location: Colombian Coffee Axis (near Manizales)
Latitude: 5°N
Longitude: 75°W
NOTE: The NCEP datasets use a 0-360° longitude convention. You must convert
75°W to this format (360 - 75 = 285°E) when setting Panoply dimensions!

REQUIRED ANALYSIS IN PANOPLY
----------------------------
Instead of a standard 2D map, you must create 1D Line Plots.
1. Open the air dataset. Double-click the 'air' variable.
2. In the "Create Plot" dialog, change the plot type from "Geo-referenced
   Longitude-Latitude" to "Line plot along one axis".
3. Set the axis to Time (so you get a 12-month profile).
4. In the Array tabs, fix Latitude to 5°N and Longitude to 285°E.
5. Extract the dataset's approximate annual mean temperature for this point.
6. Export the plot. Repeat the exact same process for the prate dataset.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/AgriRisk/

1. Temperature Line Plot:
   Filename: colombia_temp_annual.png

2. Precipitation Line Plot:
   Filename: colombia_precip_annual.png

3. Methodological Veto Memo:
   Filename: veto_memo.txt
   Required fields (use EXACTLY these key names, one per line):
     ANALYSIS_LAT: 5
     ANALYSIS_LON: 285
     DATASET_MEAN_TEMP_C: [Value in Celsius observed in the Panoply plot/array. If Panoply shows Kelvin, subtract 273.15]
     ARABICA_IDEAL_TEMP_C: 18-22
     MODEL_SUITABILITY: REJECTED
     ERROR_MECHANISM: [1-2 sentences explaining WHY the 2.5-degree grid cell shows such a high temperature compared to the real-world Andes]

SUBMISSION: Delineate clearly to override the automated underwriter.
SPECEOF

chown ga:ga /home/ga/Desktop/insurance_model_mandate.txt
chmod 644 /home/ga/Desktop/insurance_model_mandate.txt
echo "Mandate written to ~/Desktop/insurance_model_mandate.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply (empty to force agent to open datasets)
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Maximize the Panoply Sources window
focus_panoply
maximize_panoply

# Capture initial state screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="