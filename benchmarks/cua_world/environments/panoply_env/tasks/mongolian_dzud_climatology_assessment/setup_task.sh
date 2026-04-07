#!/bin/bash
echo "=== Setting up mongolian_dzud_climatology_assessment task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="mongolian_dzud_climatology_assessment"
PRATE_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
TEMP_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/DzudWarning"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify both data files exist
if [ ! -f "$PRATE_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $PRATE_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
if [ ! -f "$TEMP_FILE" ]; then
    echo "ERROR: Temperature data file not found: $TEMP_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/steppe_precip_cycle.png"
rm -f "$OUTPUT_DIR/winter_temp_january.png"
rm -f "$OUTPUT_DIR/baseline_report.txt"
rm -f /home/ga/Desktop/dzud_index_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp for anti-gaming validation
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/dzud_index_brief.txt << 'SPECEOF'
INTERNATIONAL FEDERATION OF RED CROSS AND RED CRESCENT SOCIETIES (IFRC)
ANTICIPATORY ACTION FRAMEWORK — DZUD EARLY WARNING BASELINE
=======================================================================
Request ID: IFRC-AA-2024-MNG-001
Analyst Role: Anticipatory Action Climatologist

BACKGROUND
----------
A "Dzud" is a severe Mongolian climate disaster characterized by a summer drought
(which prevents adequate pasture growth and livestock fat accumulation) followed
by extreme winter cold and snow, leading to mass livestock mortality. To calibrate
our Anticipatory Action triggers (which deploy cash to nomadic herders before the
winter peak hits), we need a climatological baseline of the annual precipitation
cycle and the peak winter cold for the central Mongolian Steppe.

DATA REQUIREMENTS
-----------------
1. Precipitation Dataset: ~/PanoplyData/prate.sfc.mon.ltm.nc
   Variable: prate (Precipitation Rate, kg/m^2/s)
2. Temperature Dataset: ~/PanoplyData/air.mon.ltm.nc
   Variable: air (Surface Air Temperature)

TARGET LOCATION
---------------
Central Mongolian Steppe: Latitude 47.0°N, Longitude 105.0°E

REQUIRED ANALYSIS & DELIVERABLES
--------------------------------
All outputs must be saved to: ~/Documents/DzudWarning/

1. Precipitation Line Plot (Annual Cycle)
   - Open the precipitation dataset in Panoply.
   - Create a 1D Line Plot for the 'prate' variable.
   - Set the X-axis to the Time dimension to show the annual cycle.
   - Set the Latitude to approximately 47.0°N and Longitude to 105.0°E.
   - Export the plot as: steppe_precip_cycle.png

2. Winter Temperature Map
   - Open the temperature dataset in Panoply.
   - Create a 2D geo-mapped plot for the 'air' variable.
   - Navigate the time dimension to the coldest winter month (January).
   - Export the map as: winter_temp_january.png

3. Baseline Report
   - Filename: baseline_report.txt
   - Inspect the plots to extract the required quantitative values.
   - Required fields (use EXACTLY these key names, one per line):
     ANALYSIS_REGION: Mongolian_Steppe
     PEAK_PASTURE_MONTH: [Month Name with highest precipitation, e.g., July]
     PEAK_PRECIP_RATE: [Approximate peak precipitation rate in kg/m^2/s, e.g., 2.5e-5]
     COLDEST_WINTER_MONTH: January
     JANUARY_MEAN_TEMP_C: [Approximate January temperature at 47N, 105E in Celsius]

Note: You can estimate the values visually from the plot axes/legends.
SPECEOF

chown ga:ga /home/ga/Desktop/dzud_index_brief.txt
chmod 644 /home/ga/Desktop/dzud_index_brief.txt

# Clean slate for Panoply
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with the first dataset pre-loaded
echo "Launching Panoply with precipitation data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$PRATE_FILE' &"

# Wait for UI, clear dialogs, and focus
wait_for_panoply 90
sleep 10
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2
focus_panoply
sleep 1

# Capture initial screenshot proving setup was successful
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="