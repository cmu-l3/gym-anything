#!/bin/bash
echo "=== Setting up east_african_bimodal_rainfall task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="east_african_bimodal_rainfall"
DATA_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/EastAfricaRainfall"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "Precipitation data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/precip_map_april.png"
rm -f "$OUTPUT_DIR/annual_cycle_lineplot.png"
rm -f "$OUTPUT_DIR/rainfall_assessment.txt"
rm -f /home/ga/Desktop/east_africa_rainfall_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis request to the desktop
cat > /home/ga/Desktop/east_africa_rainfall_request.txt << 'SPECEOF'
ICPAC SEASONAL ANALYSIS REQUEST
================================
Date: 2024-01-15
From: Dr. Aisha Mwangi, Regional Climate Outlook Forum Coordinator
To: Climate Analysis Division
Role: Agricultural Climatologist

SUBJECT: Annual Precipitation Cycle Baseline for East African Highlands

We need updated baseline documentation of the annual precipitation cycle
at our key East African monitoring point for the upcoming Greater Horn of
Africa Climate Outlook Forum (GHACOF).

REQUESTED ANALYSIS:
1. Geo-mapped precipitation plot for April (peak Long Rains month)
   showing the spatial pattern over East Africa.
2. Line plot of the full 12-month precipitation cycle at approximately
   0°N, 37.5°E (equatorial Kenya highlands).
3. Formal assessment identifying the rainfall regime.

DATASET: NCEP/NCAR Reanalysis precipitation rate climatology
FILE: ~/PanoplyData/prate.sfc.mon.ltm.nc
VARIABLE: prate (precipitation rate)
TOOL: NASA Panoply

OUTPUT DIRECTORY: ~/Documents/EastAfricaRainfall/
  - precip_map_april.png    (geo-mapped 2D plot)
  - annual_cycle_lineplot.png (1D line plot of the time series)
  - rainfall_assessment.txt  (structured report)

SCIENTIFIC CONTEXT:
Equatorial East Africa is known for its bimodal rainfall regime tied to
the twice-yearly passage of the Intertropical Convergence Zone (ITCZ).
The "Long Rains" (MAM: March-April-May) and "Short Rains" (OND: October-
November-December) define the two agricultural growing seasons.
Your analysis should confirm this pattern from the reanalysis data.

REPORT FORMAT:
Create your report exactly with these keys (one per line):
RAINFALL_PATTERN: [UNIMODAL, BIMODAL, or TRIMODAL]
LONG_RAINS_PEAK: [name of the peak month for the primary season]
SHORT_RAINS_PEAK: [name of the peak month for the secondary season]
GRID_POINT_LAT: [decimal degrees you used]
GRID_POINT_LON: [decimal degrees you used]
ASSESSMENT_VARIABLE: prate
DATA_SOURCE: NCEP/NCAR Reanalysis
AGRICULTURAL_IMPLICATIONS: Brief note on dual growing seasons
SPECEOF

chown ga:ga /home/ga/Desktop/east_africa_rainfall_request.txt
chmod 644 /home/ga/Desktop/east_africa_rainfall_request.txt
echo "Analysis request written to ~/Desktop/east_africa_rainfall_request.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with precipitation data pre-loaded
echo "Launching Panoply with precipitation data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90

# Let Panoply fully load the file
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Sources window
focus_panoply
sleep 1

# Pre-open a default geo plot for the agent (optional but helpful)
DISPLAY=:1 xdotool mousemove 728 530 click --repeat 2 --delay 100 1 2>/dev/null || true
sleep 3
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="