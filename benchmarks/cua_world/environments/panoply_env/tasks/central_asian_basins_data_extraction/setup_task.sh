#!/bin/bash
echo "=== Setting up central_asian_basins_data_extraction task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="central_asian_basins_data_extraction"
AIR_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
PRATE_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/CentralAsia"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Install scipy quietly to enable ground-truth extraction in the export script
pip3 install --quiet scipy 2>/dev/null || true

# Verify data files exist
if [ ! -f "$AIR_FILE" ] || [ ! -f "$PRATE_FILE" ]; then
    echo "ERROR: Required data files not found."
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "Air temp data: $AIR_FILE ($(stat -c%s "$AIR_FILE") bytes)"
echo "Precip data: $PRATE_FILE ($(stat -c%s "$PRATE_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/precip_map_april.png"
rm -f "$OUTPUT_DIR/basin_climatology.json"
rm -f /home/ga/Desktop/basin_data_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/basin_data_request.txt << 'SPECEOF'
CENTRAL ASIAN HYDROLOGY PROJECT
CLIMATOLOGICAL DATA EXTRACTION REQUEST
======================================
Request ID: CAHP-2024-04-EXT
Analyst Role: Hydrologist / Climate Data Analyst

BACKGROUND
----------
To parameterize our spring evaporation and runoff models for the diminishing
Aral Sea and Lake Balkhash endorheic (closed) basins, we require precise
baseline climatological data. You must extract the exact long-term mean air
temperature and precipitation rate for April at the central coordinates of
both basins.

DATA REQUIREMENTS
-----------------
- Dataset 1: NCEP/NCAR Surface Air Temperature Long-Term Mean
  File: ~/PanoplyData/air.mon.ltm.nc
  Variable: air (Monthly Mean Air Temperature)
  
- Dataset 2: NCEP/NCAR Surface Precipitation Rate Long-Term Mean
  File: ~/PanoplyData/prate.sfc.mon.ltm.nc
  Variable: prate (Precipitation Rate, kg/m^2/s)

- Target Month: April (Time index 3, since January is index 0)
- Tool: NASA Panoply

TARGET COORDINATES
------------------
1. Aral Sea Region:
   Latitude: 45.0°N
   Longitude: 60.0°E

2. Lake Balkhash Region:
   Latitude: 45.0°N
   Longitude: 75.0°E

INSTRUCTIONS
------------
1. Open the air temperature dataset in Panoply. Navigate to April.
2. Extract the exact numerical air temperature values at the two target coordinates.
   (Tip: You can use Panoply's 'Array' tab to view the raw data grid, or hover your
   mouse over the exact coordinates on a plot and read the tooltip value).
3. Repeat the process for the precipitation dataset to extract the precipitation
   rates for April at the same coordinates.
4. Export a regional map plot of the April precipitation zoomed to Central Asia.
5. Compile your findings into a strict JSON file format.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved exactly to: ~/Documents/CentralAsia/

1. Regional Precipitation Map (April):
   Filename: precip_map_april.png

2. Climatology Data Report:
   Filename: basin_climatology.json
   Format MUST exactly match the following schema (replace 0.0 with your extracted floats):
   {
     "aral_region": {
       "temp_value": 0.0,
       "precip_value": 0.0
     },
     "balkhash_region": {
       "temp_value": 0.0,
       "precip_value": 0.0
     }
   }

SUBMISSION: Due by end of session.
SPECEOF

chown ga:ga /home/ga/Desktop/basin_data_request.txt
chmod 644 /home/ga/Desktop/basin_data_request.txt
echo "Data extraction request written to ~/Desktop/basin_data_request.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with air temperature data pre-loaded
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$AIR_FILE' &"

# Wait for Panoply to start
wait_for_panoply 60
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Focus the Sources window
focus_panoply
sleep 1

# Take initial screenshot showing Panoply open
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="