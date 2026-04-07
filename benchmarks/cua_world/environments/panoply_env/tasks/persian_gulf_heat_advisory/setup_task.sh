#!/bin/bash
echo "=== Setting up persian_gulf_heat_advisory task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="persian_gulf_heat_advisory"
SST_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
AIR_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/GulfHeat"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data files exist
if [ ! -f "$SST_FILE" ]; then
    echo "ERROR: SST data file not found: $SST_FILE"
    exit 1
fi
if [ ! -f "$AIR_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $AIR_FILE"
    exit 1
fi

echo "Data files verified."

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/gulf_sst_august.png"
rm -f "$OUTPUT_DIR/gulf_airtemp_august.png"
rm -f "$OUTPUT_DIR/heat_advisory_report.txt"
rm -f /home/ga/Desktop/gulf_heat_advisory_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis brief to the desktop
cat > /home/ga/Desktop/gulf_heat_advisory_request.txt << 'SPECEOF'
ILO / WMO JOINT MARITIME SAFETY INITIATIVE
SEASONAL HEAT ADVISORY REQUEST
==========================================
Request ID: ILO-WMO-2024-AUG-001
Analyst Role: Port Meteorologist / Occupational Health Specialist
Region: Persian Gulf / Arabian Gulf basin

BACKGROUND
----------
Maritime operations and port activities in the Persian Gulf face severe thermal hazard conditions during the summer months. To establish appropriate work-rest cycle baselines and outdoor work restrictions for August, a dual-variable thermal assessment is required.

You must evaluate both the Sea Surface Temperature (SST) and Surface Air Temperature in the Persian Gulf region.

DATA REQUIREMENTS
-----------------
You will need to open TWO datasets in Panoply for this assessment:

1. Sea Surface Temperature (Marine Hazard)
   File: ~/PanoplyData/sst.ltm.1991-2020.nc
   Variable: sst (Sea Surface Temperature, degrees Celsius)

2. Surface Air Temperature (Terrestrial/Port Hazard)
   File: ~/PanoplyData/air.mon.ltm.nc
   Variable: air (Surface Air Temperature, degrees Celsius)

Target Time Period: August (Time Index 7 in these files)
Target Region: Persian Gulf basin (~23°N–31°N, 47°E–57°E)

HEAT RISK CLASSIFICATION GUIDANCE
---------------------------------
- EXTREME: Sustained SST > 32.0°C AND Air Temperature > 35.0°C
- VERY_HIGH: Sustained SST > 30.0°C AND Air Temperature > 32.0°C
- HIGH: Sustained SST > 28.0°C AND Air Temperature > 30.0°C
- MODERATE: Sustained SST < 28.0°C AND Air Temperature < 30.0°C

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/GulfHeat/

1. Regional SST Map (August):
   Filename: gulf_sst_august.png
   (Zoom into the Persian Gulf region and export the plot via File > Save Image As)

2. Regional Air Temperature Map (August):
   Filename: gulf_airtemp_august.png
   (Zoom into the Persian Gulf region and export the plot)

3. Heat Advisory Report:
   Filename: heat_advisory_report.txt
   Required fields (use EXACTLY these key names, one per line):
     ASSESSMENT_REGION: Persian Gulf
     ASSESSMENT_MONTH: August
     PEAK_SST_C: [Peak SST value you observe in the Gulf, e.g., 33.5]
     PEAK_AIR_TEMP_C: [Peak air temp value you observe around the Gulf, e.g., 36.2]
     HEAT_RISK_LEVEL: [EXTREME, VERY_HIGH, HIGH, or MODERATE based on guidance]
     OUTDOOR_WORK_RESTRICTION: [Write a 1-sentence recommendation for outdoor workers]
     DATA_SOURCES: [List the two data files used]
SPECEOF

chown ga:ga /home/ga/Desktop/gulf_heat_advisory_request.txt
chmod 644 /home/ga/Desktop/gulf_heat_advisory_request.txt
echo "Advisory request written to ~/Desktop/gulf_heat_advisory_request.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply (empty workspace, agent must open files themselves or drag/drop)
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh &"

# Wait for Panoply to start
wait_for_panoply 90

# Let Panoply fully load
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Focus and maximize Panoply Sources window
focus_panoply
maximize_panoply
sleep 2

# Take initial screenshot showing empty Panoply and desktop instruction file
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="