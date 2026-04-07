#!/bin/bash
echo "=== Setting up atlantic_hurricane_mdr_extraction task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="atlantic_hurricane_mdr_extraction"
DATA_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
OUTPUT_DIR="/home/ga/Documents/HurricaneResearch"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: SST data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "SST data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs
rm -f "$OUTPUT_DIR/mdr_sst_annual.csv"
rm -f "$OUTPUT_DIR/mdr_map_september.png"
rm -f "$OUTPUT_DIR/mdr_thermal_report.txt"
rm -f /home/ga/Desktop/mdr_extraction_request.txt

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/mdr_extraction_request.txt << 'SPECEOF'
NATIONAL HURRICANE CENTER — THERMODYNAMIC EXTRACTION REQUEST
=============================================================
Request ID: NHC-2024-MDR-01
Role: Tropical Meteorologist
Priority: HIGH

BACKGROUND
----------
We need to assess the climatological cyclogenesis window for the Atlantic Main Development Region (MDR). Tropical cyclones generally require a Sea Surface Temperature (SST) of at least 26.5°C to form and sustain themselves. You are required to extract a 1D time-series profile for a specific coordinate in the MDR, analyze it to determine which months exceed this threshold, and produce a standard 2D regional map for the peak month (September).

DATA REQUIREMENTS
-----------------
- Dataset: NOAA OI SST v2 Long-Term Mean (1991-2020)
  File location: ~/PanoplyData/sst.ltm.1991-2020.nc
  Variable: sst (Sea Surface Temperature, degrees Celsius)
- Tool: NASA Panoply

EXTRACTION COORDINATES
-----------------------
- Latitude: 15.5°N
- Longitude: 320.5°E (Note: The dataset uses a 0-360° grid. 320.5°E corresponds to 39.5°W or approximately 40°W)

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/HurricaneResearch/

1. 1D Time-Series CSV Export:
   Filename: mdr_sst_annual.csv
   (In Panoply, create a "Line plot along one axis" for Time at the specified coordinates, then use File > Export Data > as CSV to save the raw values)

2. 2D Regional Map for September:
   Filename: mdr_map_september.png
   (Create a standard geo-mapped plot for September, which is time index 8, and export the image)

3. Thermal Analysis Report:
   Filename: mdr_thermal_report.txt
   Analyze the exported CSV to determine the peak SST and the months exceeding the threshold.
   Required fields (use EXACTLY these key names, one per line):
     EXTRACTION_LAT: 15.5
     EXTRACTION_LON: 320.5
     PEAK_SST_VALUE: [The highest temperature value found in your CSV, e.g., 28.2]
     CYCLOGENESIS_MONTHS: [Comma-separated list of months where SST >= 26.5°C, e.g., August, September, October]

Submit immediately.
SPECEOF

chown ga:ga /home/ga/Desktop/mdr_extraction_request.txt
chmod 644 /home/ga/Desktop/mdr_extraction_request.txt

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with SST data pre-loaded
echo "Launching Panoply with SST data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 60
sleep 5

# Focus the Sources window
focus_panoply
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

echo "Setup complete."