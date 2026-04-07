#!/bin/bash
echo "=== Setting up datacenter_free_cooling_site_selection task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="datacenter_free_cooling_site_selection"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/DataCenter"
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
rm -f "$OUTPUT_DIR/europe_july_temp.png"
rm -f "$OUTPUT_DIR/europe_jan_temp.png"
rm -f "$OUTPUT_DIR/site_selection_report.txt"
rm -f /home/ga/Desktop/site_selection_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the engineering brief to the desktop
cat > /home/ga/Desktop/site_selection_brief.txt << 'SPECEOF'
HYPERSCALE INFRASTRUCTURE ENGINEERING — SITE SELECTION BRIEF
============================================================
Project: EU-NORTH Free-Cooling Data Center
Analyst Role: Infrastructure Site Selection Engineer
Status: ACTIVE EVALUATION

BACKGROUND
----------
Cooling systems account for up to 40% of a data center's total energy consumption.
Our firm is planning a new hyperscale data center in Europe. To meet our aggressive
PUE (Power Usage Effectiveness) targets, the facility must operate using 100% 
"free cooling" (drawing outside ambient air rather than using mechanical chillers).

Hardware limits require that the ambient air temperature never significantly
exceed 15°C (288.15 Kelvin) on a climatological mean basis, even during the peak
of summer. 

CANDIDATE LOCATIONS
-------------------
1. Ireland (Dublin region)
2. Denmark (Copenhagen region)
3. Iceland (Reykjavik region)
4. Netherlands (Amsterdam region)

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Surface Air Temperature Long-Term Mean
  File: ~/PanoplyData/air.mon.ltm.nc
  Variable: air (Air Temperature)
  NOTE: This dataset native units are in Kelvin (K). 
  The 15°C threshold is equivalent to 288.15 K.
- Tool: NASA Panoply

ANALYSIS PROCEDURE
------------------
1. Open the 'air' variable in Panoply as a georeferenced Longitude-Latitude plot.
2. Zoom the map view to focus on Europe (approx 35°N to 75°N, 15°W to 30°E).
3. Evaluate the winter baseline by checking the January timeframe (time index 0).
4. Export the January plot.
5. Evaluate the summer maximum by checking the July timeframe (time index 6).
6. Compare the candidate locations against the 288.15 K (15°C) threshold on the July plot.
7. Export the July plot.
8. Identify which candidate location remains safely BELOW the 15°C (288.15 K) threshold
   during July.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/DataCenter/

1. Summer peak temperature plot (July):
   Filename: europe_july_temp.png

2. Winter baseline temperature plot (January):
   Filename: europe_jan_temp.png

3. Site Selection Report:
   Filename: site_selection_report.txt
   Required fields (use EXACTLY these key names, one per line):
     ASSESSMENT_MONTH: July
     THRESHOLD_TEMP: 15C / 288.15K
     SELECTED_CANDIDATE: [Candidate name from the list above that meets criteria]
     RATIONALE: [Brief 1-sentence explanation of why it was chosen based on the map]
SPECEOF

chown ga:ga /home/ga/Desktop/site_selection_brief.txt
chmod 644 /home/ga/Desktop/site_selection_brief.txt
echo "Engineering brief written to ~/Desktop/site_selection_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with air temp data pre-loaded
echo "Launching Panoply with data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' > /dev/null 2>&1 &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

focus_panoply
sleep 1

# Take initial screenshot showing clean state
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="