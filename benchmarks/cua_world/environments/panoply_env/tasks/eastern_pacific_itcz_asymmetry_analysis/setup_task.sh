#!/bin/bash
echo "=== Setting up eastern_pacific_itcz_asymmetry_analysis task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="eastern_pacific_itcz_asymmetry_analysis"
DATA_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/ITCZ_Study"
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

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/epacific_precip_jan.png"
rm -f "$OUTPUT_DIR/epacific_precip_jul.png"
rm -f "$OUTPUT_DIR/itcz_report.txt"
rm -f /home/ga/Desktop/itcz_asymmetry_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis brief to the desktop
cat > /home/ga/Desktop/itcz_asymmetry_brief.txt << 'SPECEOF'
SCRIPPS INSTITUTION OF OCEANOGRAPHY
TROPICAL CLIMATOLOGY RESEARCH UNIT — ANALYSIS BRIEF
===================================================
Project: Equatorial Cold Tongue and ITCZ Asymmetry
Analyst: Tropical Climatologist

BACKGROUND
----------
In most regions of the globe, the Intertropical Convergence Zone (ITCZ) follows 
the sun, migrating into the summer hemisphere. However, in the Eastern Pacific 
Ocean, the presence of the equatorial cold tongue severely disrupts this pattern. 
We are preparing a review paper on this climatological anomaly and need formal 
documentation showing the precise latitudinal position of the ITCZ in both 
January and July.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Precipitation Rate
  File: ~/PanoplyData/prate.sfc.mon.ltm.nc
  Variable: prate (Surface Precipitation Rate, kg/m²/s)
- Tool: NASA Panoply

REQUIRED ANALYSIS
-----------------
1. Open the precipitation dataset in Panoply.
2. Navigate to January (time index 0) and zoom/center the map specifically on 
   the Eastern Pacific Ocean (approximately between longitudes 200° and 280° 
   in the dataset's 0-360° convention, or the ocean region directly west of 
   Central/South America).
3. Export the January precipitation plot.
4. Navigate to July (time index 6), maintaining the Eastern Pacific zoom.
5. Export the July precipitation plot.
6. Observe the latitude of the peak precipitation band (the ITCZ) in both months.
7. Write the formal ITCZ asymmetry report.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/ITCZ_Study/

1. January Eastern Pacific plot:
   Filename: epacific_precip_jan.png

2. July Eastern Pacific plot:
   Filename: epacific_precip_jul.png

3. ITCZ Asymmetry Report:
   Filename: itcz_report.txt
   Required fields (use EXACTLY these key names, one per line):
     ANALYSIS_REGION: Eastern Pacific
     JAN_ITCZ_LAT: [approximate latitude of the ITCZ in January, e.g., 4N]
     JUL_ITCZ_LAT: [approximate latitude of the ITCZ in July, e.g., 12N]
     CROSSES_EQUATOR: [YES or NO — does the ITCZ cross into the Southern Hemisphere in this region?]
     DRIVING_MECHANISM: [1-2 sentences explaining the anomaly]
SPECEOF

chown ga:ga /home/ga/Desktop/itcz_asymmetry_brief.txt
chmod 644 /home/ga/Desktop/itcz_asymmetry_brief.txt
echo "Analysis brief written to ~/Desktop/itcz_asymmetry_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with the data pre-loaded
echo "Launching Panoply with precipitation data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 10

# Dismiss startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Sources window
focus_panoply
sleep 1

# Pre-open the default plot for the agent to save time
echo "Selecting 'prate' variable to pre-open a geo-mapped plot..."
DISPLAY=:1 xdotool mousemove 728 530 click --repeat 2 --delay 100 1 2>/dev/null || true
sleep 3
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 5

# Capture initial state screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="