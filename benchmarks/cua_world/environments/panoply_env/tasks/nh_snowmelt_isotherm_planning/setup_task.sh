#!/bin/bash
echo "=== Setting up nh_snowmelt_isotherm_planning task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="nh_snowmelt_isotherm_planning"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/SnowmeltPlan"
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
rm -f "$OUTPUT_DIR/air_temp_february.png"
rm -f "$OUTPUT_DIR/air_temp_march.png"
rm -f "$OUTPUT_DIR/air_temp_april.png"
rm -f "$OUTPUT_DIR/snowmelt_timing_report.txt"
rm -f /home/ga/Desktop/snowmelt_briefing_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp (anti-gaming)
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the briefing request to the desktop
cat > /home/ga/Desktop/snowmelt_briefing_request.txt << 'SPECEOF'
BUREAU OF RECLAMATION — PACIFIC NORTHWEST REGIONAL OFFICE
Spring Runoff Forecast Briefing — Operations Planning Document
==============================================================
Request ID: USBR-2024-SMLT-001
Analyst Role: Hydrologic Engineer
Priority: HIGH — Pre-release scheduling required

BACKGROUND
----------
Spring snowmelt generates 60–75% of the annual streamflow in the Columbia River
Basin. Reservoir operators at Grand Coulee, Bonneville, and The Dalles need to
begin pre-release schedules 4–6 weeks before peak snowmelt to avoid overtopping.
The key meteorological indicator is when surface air temperatures consistently
cross the 0°C (273.15 K) melting threshold across the basin's mountain headwaters
(approximately 42-52°N, 114-122°W).

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Derived Surface Monthly Long-Term Mean
  File: ~/PanoplyData/air.mon.ltm.nc
  Variable: air (Surface Air Temperature, units: Kelvin)
  Time steps to analyze: 1 (February), 2 (March), 3 (April)
- Tool: NASA Panoply

ANALYSIS PROCEDURE
------------------
1. Open the 'air' variable in Panoply as a geo-referenced map.
2. Customize the color scale to clearly highlight the freezing point boundary
   (0°C = 273.15 K). You may need to adjust the min/max range or center the
   color map on 273.15 K to make this boundary obvious to operations managers.
3. Export separate maps for February, March, and April.
4. Compare the three maps to determine which month represents the onset of
   widespread snowmelt (temperatures transitioning above freezing) in the basin.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/SnowmeltPlan/

1. Three temperature map plots:
   - air_temp_february.png
   - air_temp_march.png
   - air_temp_april.png
   (Export via File > Save Image As in the Panoply plot window)

2. Snowmelt timing report:
   Filename: snowmelt_timing_report.txt
   Required fields (use EXACTLY these key names, one per line):
     TARGET_BASIN: Columbia_River
     LATITUDE_RANGE: 42-52N
     TEMPERATURE_UNIT: [Kelvin or Celsius - whichever you reference]
     FREEZING_THRESHOLD: [Numeric value representing freezing in your chosen unit]
     MONTHS_COMPARED: February, March, April
     SNOWMELT_ONSET_MONTH: [The specific month when temps cross freezing]
     ONSET_EVIDENCE: [1-2 sentences describing the isotherm transition]
     OPERATIONAL_RECOMMENDATION: Begin pre-release operations 4 weeks prior.

SUBMISSION DEADLINE: EOD
SPECEOF

chown ga:ga /home/ga/Desktop/snowmelt_briefing_request.txt
chmod 644 /home/ga/Desktop/snowmelt_briefing_request.txt
echo "Briefing request written to ~/Desktop/snowmelt_briefing_request.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with air temperature data pre-loaded
echo "Launching Panoply with air temperature data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Sources window
focus_panoply
sleep 1

# Take an initial screenshot showing the setup state
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="