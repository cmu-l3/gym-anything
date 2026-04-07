#!/bin/bash
echo "=== Setting up ocean_gyre_thermal_asymmetry task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="ocean_gyre_thermal_asymmetry"
DATA_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
OUTPUT_DIR="/home/ga/Documents/GyreStudy"
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

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/north_atlantic_feb.png"
rm -f "$OUTPUT_DIR/thermal_asymmetry_report.txt"
rm -f /home/ga/Desktop/oceanography_lab_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the lab request to the desktop
cat > /home/ga/Desktop/oceanography_lab_request.txt << 'SPECEOF'
PHYSICAL OCEANOGRAPHY 301 — LAB PREPARATION REQUEST
===================================================
Role: Lab Teaching Assistant
Topic: Ocean Gyre Thermal Asymmetry & Boundary Currents

BACKGROUND
----------
I am preparing the grading rubric for next week's undergraduate lab on the 
North Atlantic subtropical and subpolar gyres. The students will use NOAA 
climatology data to observe how western and eastern boundary currents transport 
heat differently depending on the latitude.

I need you to extract the exact baseline temperatures from our reference dataset 
to create the answer key. 

DATA REQUIREMENTS
-----------------
- Dataset: NOAA OI SST v2 Long-Term Mean (1991-2020)
  File: ~/PanoplyData/sst.ltm.1991-2020.nc
  Variable: sst (Sea Surface Temperature, degrees Celsius)
- Target month: February (when Northern Hemisphere thermal contrast is strongest)
- Tool: NASA Panoply

REQUIRED ANALYSIS
-----------------
1. Open the SST dataset in Panoply and create a geo-mapped plot.
2. Navigate the time dimension to February.
3. Zoom the map to the North Atlantic Ocean.
4. Export the regional map to: ~/Documents/GyreStudy/north_atlantic_feb.png
5. Using Panoply's data interrogation tools (either hovering over the map for the 
   tooltip OR opening the "Array 1" tab to view the raw grid), find the SST 
   at the following four approximate coordinates:
   
   - Subtropical West: 30°N, 78°W (Off the coast of Florida/Georgia)
   - Subtropical East: 30°N, 12°W (Off the coast of Morocco)
   
   - Mid-latitude West: 45°N, 60°W (Off the coast of Nova Scotia)
   - Mid-latitude East: 45°N, 12°W (Bay of Biscay / off France)

6. Based on these temperatures, logically conclude which side of the ocean basin 
   is warmer at each latitude (WEST or EAST).

DELIVERABLE FORMAT
------------------
Save your findings to: ~/Documents/GyreStudy/thermal_asymmetry_report.txt

The text file MUST contain EXACTLY these keys, one per line:
ANALYSIS_MONTH: February
SUB_WEST_30N_78W_C: [numeric value in °C]
SUB_EAST_30N_12W_C: [numeric value in °C]
SUBTROPICAL_WARMER_SIDE: [WEST or EAST]
MID_WEST_45N_60W_C: [numeric value in °C]
MID_EAST_45N_12W_C: [numeric value in °C]
MIDLATITUDE_WARMER_SIDE: [WEST or EAST]

Thank you,
Prof. Reynolds
SPECEOF

chown ga:ga /home/ga/Desktop/oceanography_lab_request.txt
chmod 644 /home/ga/Desktop/oceanography_lab_request.txt

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with SST data pre-loaded
echo "Launching Panoply with SST data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Sources window and maximize
focus_panoply
maximize_panoply
sleep 1

# Select 'sst' variable and pre-open a geo-mapped plot to help agent start
# In 1920x1080, sst is typically at y=530
DISPLAY=:1 xdotool mousemove 728 530 click --repeat 2 --delay 100 1 2>/dev/null || true
sleep 3
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 8

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="