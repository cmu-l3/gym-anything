#!/bin/bash
echo "=== Setting up precipitation_regime_line_plot_comparison task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="precipitation_regime_line_plot_comparison"
DATA_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/PrecipRegimes"
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
rm -f "$OUTPUT_DIR/amazon_annual_precip.png"
rm -f "$OUTPUT_DIR/mediterranean_annual_precip.png"
rm -f "$OUTPUT_DIR/regime_comparison_report.txt"
rm -f /home/ga/Desktop/precip_regime_assignment.txt
echo "Cleaned up any pre-existing outputs"

# Record task start timestamp (Anti-gaming measure)
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the assignment document to the desktop
cat > /home/ga/Desktop/precip_regime_assignment.txt << 'SPECEOF'
HYDROLOGY RESEARCH LAB — PRECIPITATION REGIME ANALYSIS
======================================================
Analyst Role: Hydrology PhD Student
Project: Global Precipitation Patterns (Dissertation Chapter 2)

BACKGROUND
----------
You need to produce a comparison figure for your dissertation showing the difference
between two archetypal precipitation regimes: the near-continuous rainfall of the
humid tropics (Amazon Basin) and the pronounced summer drought of a Mediterranean
climate (Eastern Mediterranean / Greece).

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Long-Term Mean Precipitation Rate
  File: ~/PanoplyData/prate.sfc.mon.ltm.nc
  Variable: prate (Surface Precipitation Rate, kg/m²/s)
- Tool: NASA Panoply

REQUIRED WORKFLOW IN PANOPLY
----------------------------
Unlike standard geo-referenced maps, you need to create 1D LINE PLOTS to show the
annual 12-month cycle at specific locations.
1. Select the 'prate' variable in Panoply and click "Create Plot".
2. IMPORTANT: In the plot type dialog, change from "Create a lonlat map" to
   "Create a line plot along one axis".
3. Configure the line plot so the Time dimension is on the x-axis.
4. Fix the Latitude and Longitude dimensions to the coordinates below using the
   sliders/dropdowns in the Array controls.

LOCATIONS TO ANALYZE
--------------------
1. Amazon Basin: Latitude ≈ -3° (3°S), Longitude ≈ 300° (equivalent to 60°W in 0-360 format)
2. Eastern Mediterranean: Latitude ≈ 38°N, Longitude ≈ 20°E

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/PrecipRegimes/

1. Amazon line plot export:
   Filename: amazon_annual_precip.png

2. Mediterranean line plot export:
   Filename: mediterranean_annual_precip.png

3. Regime comparison report:
   Filename: regime_comparison_report.txt
   Required fields (use EXACTLY these key names, one per line):
     AMAZON_LAT: [approx latitude used]
     AMAZON_LON: [approx longitude used]
     AMAZON_REGIME: [classify the regime: e.g., tropical wet, equatorial, savanna, etc.]
     AMAZON_WETTEST_SEASON: [season or months of peak rainfall]
     MED_LAT: [approx latitude used]
     MED_LON: [approx longitude used]
     MED_REGIME: [classify the regime: e.g., Mediterranean, winter-wet, continental, etc.]
     MED_DRY_SEASON: [the pronounced dry season months, e.g., summer, JJA]
     REGIME_CONTRAST: [1-2 sentences summarizing how they differ]
     DATA_SOURCE: NCEP/NCAR prate.sfc.mon.ltm.nc
SPECEOF

chown ga:ga /home/ga/Desktop/precip_regime_assignment.txt
chmod 644 /home/ga/Desktop/precip_regime_assignment.txt

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 2

# Launch Panoply with precipitation data pre-loaded
echo "Launching Panoply with precipitation data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "panoply"; then
        echo "Panoply window detected"
        break
    fi
    sleep 2
done

# Let Panoply fully load the file
sleep 8

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize and Focus the Panoply window
DISPLAY=:1 wmctrl -r "Panoply" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Panoply" 2>/dev/null || true

# Pre-select the prate variable (at roughly center screen) to help the agent start
DISPLAY=:1 xdotool mousemove 728 530 click 1 2>/dev/null || true
sleep 1

# Take initial screenshot to prove starting state
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="