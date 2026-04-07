#!/bin/bash
echo "=== Setting up ebus_fisheries_resource_assessment task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="ebus_fisheries_resource_assessment"
DATA_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
OUTPUT_DIR="/home/ga/Documents/UpwellingAssessment"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: SST data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "SST data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory owned by ga
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/global_sst_july.png"
rm -f "$OUTPUT_DIR/humboldt_upwelling_july.png"
rm -f "$OUTPUT_DIR/upwelling_report.txt"
rm -f /home/ga/Desktop/ebus_fisheries_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis request spec file to the desktop
cat > /home/ga/Desktop/ebus_fisheries_request.txt << 'SPECEOF'
FAO MARINE RESOURCES ASSESSMENT GROUP
STATE OF WORLD FISHERIES AND AQUACULTURE (SOFIA) - ANALYSIS REQUEST
===================================================================
Request ID: FAO-SOFIA-2024-EBUS
Analyst Role: Fisheries Resource Scientist
Priority: HIGH — SOFIA Report Publication Cycle

BACKGROUND
----------
Eastern Boundary Upwelling Systems (EBUS) cover less than 2% of the global
ocean area but sustain approximately 20% of the world's marine fish catch.
These systems (e.g., Humboldt, Benguela, California, Canary currents) are
driven by persistent equatorward winds that pull deep, nutrient-laden water
to the surface along continental western margins. This nutrient injection fuels
massive phytoplankton blooms, supporting immense populations of small pelagic
fishes (sardines, anchovies) and top predators.

You are required to characterize the climatological baseline of these
upwelling zones during July (a month when both Humboldt and Benguela are active)
to support the upcoming regional fisheries quota recommendations.

DATA REQUIREMENTS
-----------------
- Dataset: NOAA OI SST v2 Long-Term Mean (1991-2020)
  File location: ~/PanoplyData/sst.ltm.1991-2020.nc
  Variable: sst (Sea Surface Temperature, degrees Celsius)
  Time step: July
- Tool: NASA Panoply

ANALYSIS PROCEDURE
------------------
1. Identify Eastern Boundary Upwelling Systems visually by their distinct SST signature
   (narrow bands of anomalous temperatures along continental margins).
2. Generate a global overview of SST patterns.
3. Generate a regional focus plot on the Humboldt Current (off the west coast
   of South America, approx 0–50°S, 60–90°W), Earth's most productive fishery.
4. Extract representative SST values to characterize the intensity of the upwelling
   relative to the adjacent open ocean at the same latitude.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/UpwellingAssessment/

1. Global SST map for July:
   Filename: global_sst_july.png
   (Export a global Panoply plot showing the SST variable for July)

2. Zoomed SST map of the Humboldt Current upwelling:
   Filename: humboldt_upwelling_july.png
   (Adjust the plot area in Panoply to focus on the Southeast Pacific)

3. Upwelling Fisheries Assessment Report:
   Filename: upwelling_report.txt
   Required fields (use EXACTLY these key names, one per line):
     ASSESSMENT_MONTH: July
     PRIMARY_EBUS: [Name a major upwelling system you identified, e.g., Humboldt]
     UPWELLING_SST_C: [Approximate SST in the coastal upwelling zone, e.g., 14.5]
     ADJACENT_OCEAN_SST_C: [Approximate SST in the open ocean at the same latitude]
     SST_ANOMALY_SIGN: [NEGATIVE or POSITIVE — is the coastal upwelling colder or warmer than the open ocean?]
     PRODUCTIVITY_CORRELATION: [POSITIVE or NEGATIVE — based on marine biogeochemistry, does this upwelled water support HIGH (positive) or LOW (negative) biological productivity?]
     NUM_EBUS_IDENTIFIED: [Integer number of distinct EBUS zones you can spot globally in July]

SCIENTIFIC GUIDANCE
-------------------
Think carefully about the physical and biological mechanisms of upwelling before
answering PRODUCTIVITY_CORRELATION and SST_ANOMALY_SIGN. Deep ocean water has distinct
temperature and nutrient properties compared to surface water.
SPECEOF

chown ga:ga /home/ga/Desktop/ebus_fisheries_request.txt
chmod 644 /home/ga/Desktop/ebus_fisheries_request.txt
echo "Fisheries assessment request written to ~/Desktop/ebus_fisheries_request.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with SST data pre-loaded
echo "Launching Panoply with SST data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90

# Let Panoply fully load
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Panoply Sources window
focus_panoply
sleep 1

# Select the 'sst' variable to pre-open a geo-mapped plot
echo "Selecting 'sst' variable to pre-open a geo-mapped plot..."
DISPLAY=:1 xdotool mousemove 728 530 click --repeat 2 --delay 100 1 2>/dev/null || true
sleep 3

# Press Enter to create the default geo-referenced plot
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 8

echo "Task setup complete. Ready for agent execution."