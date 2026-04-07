#!/bin/bash
echo "=== Setting up aviation_altimetry_terrain_clearance task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="aviation_altimetry_terrain_clearance"
DATA_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/AviationSafety"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: SLP data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "SLP data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs
rm -f "$OUTPUT_DIR/nh_jan_slp_map.png"
rm -f "$OUTPUT_DIR/altimetry_hazard_report.txt"
rm -f /home/ga/Desktop/altimetry_safety_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the safety brief to the desktop
cat > /home/ga/Desktop/altimetry_safety_brief.txt << 'SPECEOF'
ICAO AVIATION SAFETY INSPECTION — ALTIMETRY HAZARD ASSESSMENT
=============================================================
Brief ID: ICAO-ALT-2024-JAN-002
Analyst Role: Aviation Safety Inspector
Topic: Winter Barometric Altimeter Error - Northern Hemisphere

BACKGROUND
----------
Aircraft barometric altimeters are calibrated to the International Standard 
Atmosphere (ISA), which assumes a sea-level pressure of 1013 hPa. When an 
aircraft flies into a region with lower-than-standard pressure, the altimeter 
will indicate a higher altitude than the aircraft's true altitude. This poses 
a significant risk for Controlled Flight Into Terrain (CFIT) during winter IFR 
approaches ("High to Low, Look Out Below").

You must identify the lowest climatological mean pressure system in the 
Northern Hemisphere during January to calculate the maximum theoretical terrain 
clearance error for uncorrected altimeters.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Long-Term Mean Sea Level Pressure
  File: ~/PanoplyData/slp.mon.ltm.nc
  Variable: slp (Sea Level Pressure, mb/hPa)
  Time period: January
- Tool: NASA Panoply

REQUIRED ANALYSIS
-----------------
1. Create a geo-mapped plot of SLP for January.
2. Apply a Northern Hemisphere map projection (e.g., North Polar Stereographic) 
   to view the entire winter hemisphere.
3. Identify the deepest low-pressure systems (typically the Aleutian Low or Icelandic Low).
4. Use Panoply's array view or data cursor to extract the minimum mean SLP (in hPa) 
   at the center of the deepest low.
5. Calculate the altimeter error using this rule of thumb:
   Error (ft) = (1013 - Minimum_SLP) * 30
   (Note: 1 hPa deviation = ~30 feet of altitude error)

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/AviationSafety/

1. Northern Hemisphere SLP map:
   Filename: nh_jan_slp_map.png

2. Hazard Assessment Report:
   Filename: altimetry_hazard_report.txt
   Required fields (use EXACTLY these key names, one per line):
     ASSESSMENT_MONTH: January
     PRIMARY_HAZARD_SYSTEM: [Name of the low pressure system/region you found]
     MIN_MEAN_SLP_HPA: [Integer value of the lowest pressure in hPa]
     MAX_ALTITUDE_ERROR_FT: [Integer value calculated from your formula]
     SAFETY_IMPLICATION: [Write TRUE_LOWER if the true altitude is lower than indicated, or TRUE_HIGHER if true altitude is higher]

SPECEOF

chown ga:ga /home/ga/Desktop/altimetry_safety_brief.txt
chmod 644 /home/ga/Desktop/altimetry_safety_brief.txt

# Launch Panoply
pkill -f "Panoply.jar" 2>/dev/null || true
sleep 2

echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 10

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

focus_panoply
maximize_panoply 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="