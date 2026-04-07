#!/bin/bash
echo "=== Setting up salmon_aquaculture_thermal_viability task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="salmon_aquaculture_thermal_viability"
DATA_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
OUTPUT_DIR="/home/ga/Documents/Aquaculture"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: SST data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "SST data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/sst_austral_summer_feb.png"
rm -f "$OUTPUT_DIR/sst_austral_winter_aug.png"
rm -f "$OUTPUT_DIR/thermal_viability_report.txt"
rm -f /home/ga/Desktop/aquaculture_site_evaluation.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the evaluation request spec file to the desktop
cat > /home/ga/Desktop/aquaculture_site_evaluation.txt << 'SPECEOF'
GLOBAL SEAFOOD CONGLOMERATE — ATLANTIC SALMON AQUACULTURE SITE EVALUATION
==========================================================================
Request ID: AQ-2024-SH-001
Analyst Role: Aquaculture Consultant / Marine Biologist
Subject: Thermal Viability of Southern Hemisphere Candidate Sites

BACKGROUND
----------
Our company is evaluating three candidate coastal sites in the Southern Hemisphere
for a new Atlantic Salmon (Salmo salar) aquaculture operation. Atlantic salmon
are highly sensitive to sea surface temperatures:
- They suffer lethal thermal stress at sustained temperatures > 18°C
- They experience lethal winter superchill at temperatures < 4°C
- The viable long-term rearing range is 4°C to 18°C.

You must analyze the long-term climatological Sea Surface Temperature (SST)
data to evaluate summer peak temperatures and export regional maps.

DATA REQUIREMENTS
-----------------
- Dataset: NOAA OI SST v2 Long-Term Mean (1991-2020)
  File: ~/PanoplyData/sst.ltm.1991-2020.nc
  Variable: sst (Sea Surface Temperature, degrees Celsius)
- Tool: NASA Panoply

CANDIDATE SITES TO EVALUATE
---------------------------
1. Perth, Australia Coast: 32°S, 115°E
2. Tasmania, Australia Coast: 43°S, 147°E
3. Magallanes, Chile Coast: 53°S, 75°W
   (Note: Panoply uses a 0-360° East longitude convention. 75°W is 285°E)

REQUIRED ANALYSIS
-----------------
Using Panoply, you must:
1. Export a plot of the Austral Summer (February) SST.
2. Export a plot of the Austral Winter (August) SST.
3. Use Panoply's data array view or map hover/click tools to extract the approximate
   peak summer (February) SST at the three candidate coordinates.
4. Classify the viability of each site based on the 18°C upper threshold.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/Aquaculture/

1. Austral Summer SST map:
   Filename: sst_austral_summer_feb.png

2. Austral Winter SST map:
   Filename: sst_austral_winter_aug.png

3. Thermal viability report:
   Filename: thermal_viability_report.txt
   Required fields (use EXACTLY these key names, one per line):
     PERTH_FEB_SST_C: [numeric value, e.g., 22.5]
     PERTH_VIABILITY: [TOO_HOT, TOO_COLD, or VIABLE]
     TASMANIA_FEB_SST_C: [numeric value]
     TASMANIA_VIABILITY: [TOO_HOT, TOO_COLD, or VIABLE]
     MAGALLANES_FEB_SST_C: [numeric value]
     MAGALLANES_VIABILITY: [TOO_HOT, TOO_COLD, or VIABLE]

CLASSIFICATION RULES:
- If Feb SST > 18.0°C -> TOO_HOT
- If Feb SST < 4.0°C -> TOO_COLD
- If Feb SST is 4.0°C to 18.0°C -> VIABLE

Please complete this assessment promptly.
SPECEOF

chown ga:ga /home/ga/Desktop/aquaculture_site_evaluation.txt
chmod 644 /home/ga/Desktop/aquaculture_site_evaluation.txt
echo "Evaluation request written to ~/Desktop/aquaculture_site_evaluation.txt"

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

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="