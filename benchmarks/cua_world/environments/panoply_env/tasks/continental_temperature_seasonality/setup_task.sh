#!/bin/bash
echo "=== Setting up continental_temperature_seasonality task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="continental_temperature_seasonality"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/Seasonality"
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

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/air_temp_january.png"
rm -f "$OUTPUT_DIR/air_temp_july.png"
rm -f "$OUTPUT_DIR/seasonality_report.txt"
rm -f /home/ga/Desktop/geography_lecture_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the lecture brief to the desktop
cat > /home/ga/Desktop/geography_lecture_brief.txt << 'SPECEOF'
GEOGRAPHY 101: EARTH'S CLIMATE SYSTEMS
Lecture Preparation Brief — Continental vs. Maritime Climates

Professor: Dr. Sarah Chen
Course: Introduction to Physical Geography (GEOG 101)
Lecture Date: Next Tuesday
Enrollment: 204 students

OBJECTIVE:
Create two global surface air temperature maps (January and July) and a brief
analysis identifying the region on Earth with the greatest annual temperature
range. This will illustrate the concept of "continentality" — why locations
deep within large landmasses experience extreme seasonal temperature swings
compared to oceanic locations.

DATA:
Use the NCEP/NCAR Reanalysis surface air temperature climatology located at:
  /home/ga/PanoplyData/air.mon.ltm.nc

Note: Temperature values in this dataset are in Kelvin (K). To convert to
Celsius, subtract 273.15.

DELIVERABLES:

1. January global air temperature map
   → Save as: ~/Documents/Seasonality/air_temp_january.png

2. July global air temperature map
   → Save as: ~/Documents/Seasonality/air_temp_july.png

3. Educational summary report
   → Save as: ~/Documents/Seasonality/seasonality_report.txt
   → Use the following format (one field per line):

   MAX_SEASONALITY_REGION: [region name where January-to-July temperature difference is greatest]
   JANUARY_TEMP: [approximate temperature at that location in January, with units]
   JULY_TEMP: [approximate temperature at that location in July, with units]
   ANNUAL_RANGE_C: [temperature difference in degrees Celsius]
   PHYSICAL_MECHANISM: [1-3 sentence explanation of why this region has the highest seasonality]

GUIDANCE:
- Compare the two maps carefully to find where the temperature CHANGE between
  January and July is most dramatic.
- Focus on large continental interiors in the Northern Hemisphere.
- The answer should be consistent with well-established physical geography.
SPECEOF

chown ga:ga /home/ga/Desktop/geography_lecture_brief.txt
chmod 644 /home/ga/Desktop/geography_lecture_brief.txt
echo "Lecture brief written to ~/Desktop/geography_lecture_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with air temp data pre-loaded
echo "Launching Panoply with air temperature data..."
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

# Take initial screenshot to prove app started properly
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="