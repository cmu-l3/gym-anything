#!/bin/bash
echo "=== Setting up european_heatwave_synoptic_assessment task ==="

TASK_NAME="european_heatwave_synoptic_assessment"
AIR_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
SLP_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/HeatwaveAssessment"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data files exist
if [ ! -f "$AIR_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $AIR_FILE"
    exit 1
fi
if [ ! -f "$SLP_FILE" ]; then
    echo "ERROR: SLP data file not found: $SLP_FILE"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/europe_temp_july.png"
rm -f "$OUTPUT_DIR/europe_slp_july.png"
rm -f "$OUTPUT_DIR/heatwave_assessment.txt"
rm -f /home/ga/Desktop/heatwave_preparedness_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
date +%s > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis brief to the desktop
cat > /home/ga/Desktop/heatwave_preparedness_brief.txt << 'SPECEOF'
WHO REGIONAL OFFICE FOR EUROPE / NATIONAL HEALTH PROTECTION AGENCY
SUMMER HEAT-HEALTH WARNING SYSTEM (HHWS) — SYNOPTIC ASSESSMENT BRIEF
====================================================================
Brief ID: HHWS-2024-PRE-001
Analyst Role: Heat-Health Early Warning System Officer
Priority: ROUTINE — Pre-season preparedness

BACKGROUND
----------
European heatwaves are the continent's deadliest natural hazard. Extreme summer
heat events in Europe are strongly associated with the amplification and
northeastward extension of a specific subtropical anticyclone (high-pressure
system) that brings subsidence, clear skies, and extreme temperatures to the
Mediterranean and continental interior.

To calibrate our regional Heat-Health Warning System (HHWS) thresholds, we need
to document the "normal" climatological baseline for July (the peak summer heat
month) using atmospheric reanalysis data.

DATA REQUIREMENTS
-----------------
Both datasets are located in ~/PanoplyData/:
1. Surface Air Temperature
   File: air.mon.ltm.nc
   Variable: air (Monthly Long-Term Mean Surface Air Temperature)
   NOTE: Values are in Kelvin. You must convert to degrees Celsius for the report.

2. Sea Level Pressure
   File: slp.mon.ltm.nc
   Variable: slp (Monthly Long-Term Mean Sea Level Pressure)
   NOTE: Values are in Pascals. You must convert to hectopascals (hPa) for the report.

Time step: July
Tool: NASA Panoply

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/HeatwaveAssessment/

1. July Air Temperature Map:
   Create a geo-mapped plot showing July surface air temperature over Europe.
   Filename: europe_temp_july.png

2. July Sea Level Pressure Map:
   Create a geo-mapped plot showing July sea level pressure, capturing the
   subtropical high that dominates the Atlantic/European region.
   Filename: europe_slp_july.png

3. Synoptic Assessment Report:
   Filename: heatwave_assessment.txt
   Required fields (use EXACTLY these key names, one per line):
     ASSESSMENT_PERIOD: July
     DOMINANT_PRESSURE_SYSTEM: [name of the subtropical anticyclone affecting Europe, e.g., Azores High]
     SLP_CENTER_HPA: [approximate central pressure of this high in hPa, e.g., 1024]
     SOUTHERN_EUROPE_TEMP_C: [approximate July temperature in southern Europe in °C, e.g., 28]
     HIGHEST_RISK_REGION: [name a European region most at risk from this system]
     HEATWAVE_MECHANISM: [1-2 sentences on how high pressure causes extreme heat]

SUBMISSION: Due by end of session.
SPECEOF

chown ga:ga /home/ga/Desktop/heatwave_preparedness_brief.txt
chmod 644 /home/ga/Desktop/heatwave_preparedness_brief.txt

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply empty to allow agent to load files
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh &"

# Wait for Panoply to start
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "panoply"; then
        break
    fi
    sleep 1
done
sleep 5

# Maximize Panoply Sources window
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "panoply" | awk '{print $1}' | head -1)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="