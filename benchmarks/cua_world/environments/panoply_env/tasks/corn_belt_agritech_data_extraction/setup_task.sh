#!/bin/bash
echo "=== Setting up corn_belt_agritech_data_extraction task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="corn_belt_agritech_data_extraction"
AIR_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
PRATE_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/AgTech"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify both data files exist
if [ ! -f "$AIR_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $AIR_FILE"
    exit 1
fi
if [ ! -f "$PRATE_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $PRATE_FILE"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/iowa_temp_climatology.csv"
rm -f "$OUTPUT_DIR/iowa_precip_climatology.csv"
rm -f "$OUTPUT_DIR/feature_summary.txt"
rm -f /home/ga/Desktop/agritech_data_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/agritech_data_request.txt << 'SPECEOF'
AG-YIELD PREDICTION MODEL: BASELINE DATA EXTRACTION PROTOCOL
=============================================================
Request ID: AGTECH-2024-CORN-01
Analyst Role: Agricultural Data Scientist
Target Region: US Corn Belt (Iowa)

BACKGROUND
----------
Our machine learning pipeline requires baseline climatological data (12-month
annual cycles) to normalize real-time weather feeds for our Iowa corn yield
prediction model. We need you to extract the raw 1D arrays of monthly
temperature and precipitation for our specific grid cell using NASA Panoply.

Unlike typical visual mapping, this task requires extracting the RAW NUMERICAL
DATA as CSV files for our Python pipeline.

TARGET LOCATION
---------------
- Latitude: 42°N
- Longitude: 266°E (Equivalent to 94°W in the NCEP 0-360 convention)

DATASETS
--------
1. Air Temperature: ~/PanoplyData/air.mon.ltm.nc (Variable: air)
2. Precipitation: ~/PanoplyData/prate.sfc.mon.ltm.nc (Variable: prate)

EXTRACTION PROCEDURE
--------------------
For EACH of the two datasets, you must:
1. Open the file in Panoply.
2. Select the data variable and click "Create Plot".
3. CRITICAL: When prompted, select "Line plot along one axis" (NOT a geo map).
4. Set the horizontal axis to 'Time'.
5. In the Array tabs, fix the dimensions to the Target Location (Lat ~42, Lon ~266).
6. Export the data to CSV using File > Export Data > As CSV...

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/AgTech/

1. Temperature CSV File:
   Filename: iowa_temp_climatology.csv

2. Precipitation CSV File:
   Filename: iowa_precip_climatology.csv

3. Feature Summary Report:
   Filename: feature_summary.txt
   Required fields (use EXACTLY these key names, one per line):
     ANALYSIS_LAT: [The exact latitude Panoply snapped to, e.g., 41.9]
     ANALYSIS_LON: [The exact longitude Panoply snapped to, e.g., 266.25]
     PEAK_TEMP_MONTH: [Month name or index with the highest temperature]
     PEAK_PRECIP_MONTH: [Month name or index with the highest precipitation]

SUBMISSION: Please complete immediately. The ML engineering team is waiting.
SPECEOF

chown ga:ga /home/ga/Desktop/agritech_data_request.txt
chmod 644 /home/ga/Desktop/agritech_data_request.txt
echo "AgTech analysis mandate written to ~/Desktop/agritech_data_request.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
focus_panoply

echo "=== Task setup complete ==="