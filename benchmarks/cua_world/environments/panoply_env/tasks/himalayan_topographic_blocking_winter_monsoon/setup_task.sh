#!/bin/bash
echo "=== Setting up himalayan_topographic_blocking_winter_monsoon task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="himalayan_topographic_blocking_winter_monsoon"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/LectureNotes"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "Air temperature data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/himalayan_thermal_wall_jan.png"
rm -f "$OUTPUT_DIR/himalayan_thermal_wall_july.png"
rm -f "$OUTPUT_DIR/blocking_effect_summary.txt"
rm -f /home/ga/Desktop/himalayan_blocking_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the lecture brief to the desktop
cat > /home/ga/Desktop/himalayan_blocking_brief.txt << 'SPECEOF'
PHYSICAL GEOGRAPHY DEPARTMENT — LECTURE PREP REQUEST
=====================================================
Module: GEOG 201 - Topographic Climate Controls
Topic: The Himalayan Thermal Wall & Winter Monsoon
Role: Teaching Assistant

BACKGROUND
----------
During boreal winter, the massive Siberian High anticyclone dominates Eurasian
atmospheric circulation, sending freezing continental Polar (cP) air masses
southward. However, the Himalayan mountain range and Tibetan Plateau act as an
impenetrable "thermal wall," blocking this freezing air from reaching the Indian
subcontinent. We need to demonstrate this extreme temperature gradient to students.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Long-Term Mean Surface Air Temperature
  File: ~/PanoplyData/air.mon.ltm.nc
  Variable: air (Monthly Long Term Mean Air Temperature)
- Tool: NASA Panoply

REQUIRED ANALYSIS & DELIVERABLES
--------------------------------
You must create two visualizations and extract specific data points to quantify
this topographic blocking effect. Save ALL outputs to: ~/Documents/LectureNotes/

1. January Topographic Blocking Map
   - Create a geo-mapped plot of air temperature for January.
   - Zoom/adjust the map focus to Central/South Asia (approx 10-50°N, 60-100°E).
   - Export this image as: himalayan_thermal_wall_jan.png

2. July Summer Baseline Map
   - Navigate the plot to July to demonstrate the absence of the gradient.
   - Export this image as: himalayan_thermal_wall_july.png

3. Quantitative Summary Report
   - Use Panoply's data inspection tools (Tooltip or Array view) to extract the
     mean January temperature at two specific coordinates.
   - Ensure you report values in Celsius (convert if Panoply displays Kelvin).
   - Create a text file at: blocking_effect_summary.txt
   - The file MUST contain EXACTLY these lines/keys:

PHENOMENON: Himalayan Topographic Blocking
ANALYSIS_MONTH: January
INDIA_LAT: 25N
INDIA_LON: 80E
INDIA_TEMP_C: [Extract January temp for 25N, 80E in Celsius]
TIBET_LAT: 35N
TIBET_LON: 80E
TIBET_TEMP_C: [Extract January temp for 35N, 80E in Celsius]
TEMP_DIFFERENCE: [Calculate INDIA_TEMP_C minus TIBET_TEMP_C]
WINTER_AIRMASS: Siberian High

NOTES:
- The coordinate 80E cuts straight across both Northern India and the Tibetan
  Plateau. 25N represents the protected plains of India, while 35N represents
  the freezing, exposed high-altitude plateau.
SPECEOF

chown ga:ga /home/ga/Desktop/himalayan_blocking_brief.txt
chmod 644 /home/ga/Desktop/himalayan_blocking_brief.txt
echo "Lecture brief written to ~/Desktop/himalayan_blocking_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with data pre-loaded
echo "Launching Panoply with air temperature data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90

# Let Panoply fully load
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Sources window
focus_panoply
sleep 1

# Maximize Panoply Sources window
maximize_panoply

# Take initial screenshot showing clean starting state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="