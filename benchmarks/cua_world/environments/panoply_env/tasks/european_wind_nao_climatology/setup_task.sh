#!/bin/bash
echo "=== Setting up european_wind_nao_climatology task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="european_wind_nao_climatology"
DATA_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/WindEnergy"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: SLP data file not found: $DATA_FILE"
    exit 1
fi
echo "SLP data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/north_atlantic_slp_jan.png"
rm -f "$OUTPUT_DIR/nao_baseline_report.txt"
rm -f /home/ga/Desktop/nao_analysis_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp (Anti-gaming)
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/nao_analysis_request.txt << 'SPECEOF'
EUROPEAN WIND ENERGY CONSORTIUM — NAO CLIMATOLOGY BASELINE
==========================================================
Request ID: WE-NAO-2024-01
Analyst: Wind Energy Meteorologist
Priority: HIGH — Seasonal forecast calibration

BACKGROUND
----------
Winter wind power generation across the UK, Germany, and Scandinavia is heavily
driven by the North Atlantic Oscillation (NAO). The NAO is primarily measured
by the pressure gradient between the Icelandic Low and the Azores High.

To calibrate our upcoming January wind anomaly forecasts, we require the exact
climatological baseline (long-term mean) of this pressure gradient.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Long-Term Mean Sea Level Pressure
  File location: ~/PanoplyData/slp.mon.ltm.nc
  Variable: slp (Sea Level Pressure, mb)
  Time step: January (Peak winter month)
- Tool: NASA Panoply

REQUIRED EXTRACTS (JANUARY MEAN)
--------------------------------
You must extract the exact data values at these precise coordinates:
1. Icelandic Low Reference Node: 65.0°N, 22.5°W
2. Azores High Reference Node: 37.5°N, 27.5°W

(Note: NCEP longitudes are 0-360°E. You must convert West longitudes to 360°E format.
 E.g., 10°W = 350°E. Use Panoply's Array 2D view or exact cursor hover to read values).

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/WindEnergy/

1. Regional North Atlantic Map Plot:
   Filename: north_atlantic_slp_jan.png
   - Create a geo-mapped plot of January SLP.
   - Adjust the map center/zoom or crop to focus on the North Atlantic basin
     (approximately 20°N to 75°N, 80°W to 10°E).
   - Export via File > Save Image As.

2. NAO Baseline Report:
   Filename: nao_baseline_report.txt
   Required fields (use EXACTLY these key names, one per line):
     ANALYSIS_MONTH: January
     ICELAND_NODE_LAT: 65.0N
     ICELAND_NODE_LON: 22.5W
     ICELAND_SLP_MB: [exact extracted value at this node, mb]
     AZORES_NODE_LAT: 37.5N
     AZORES_NODE_LON: 27.5W
     AZORES_SLP_MB: [exact extracted value at this node, mb]
     NAO_GRADIENT_MB: [calculated difference: Azores SLP minus Iceland SLP]
     IMPLICATION: [1-2 sentences on how a stronger gradient affects European wind power]

Ensure precision. We need the exact array values from the gridded data.
SPECEOF

chown ga:ga /home/ga/Desktop/nao_analysis_request.txt
chmod 644 /home/ga/Desktop/nao_analysis_request.txt
echo "Analysis request written to ~/Desktop/nao_analysis_request.txt"

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

# Maximize and Focus the Panoply Sources window
maximize_panoply
focus_panoply
sleep 1

# Take initial screenshot showing Panoply open with data
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="