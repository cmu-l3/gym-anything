#!/bin/bash
echo "=== Setting up himalayan_summit_weather_window task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="himalayan_summit_weather_window"
OUTPUT_DIR="/home/ga/Documents/Expedition"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Data files required
PRATE_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
AIR_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"

# Verify datasets exist
if [ ! -f "$PRATE_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $PRATE_FILE"
    exit 1
fi
if [ ! -f "$AIR_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $AIR_FILE"
    exit 1
fi

# Create target output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs
rm -f "$OUTPUT_DIR/himalaya_precip_may.png"
rm -f "$OUTPUT_DIR/himalaya_precip_july.png"
rm -f "$OUTPUT_DIR/himalaya_temp_may.png"
rm -f "$OUTPUT_DIR/summit_report.txt"
rm -f /home/ga/Desktop/expedition_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp for anti-gaming
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/expedition_brief.txt << 'SPECEOF'
HIMALAYAN EXPEDITION - WEATHER PLANNING BRIEF
=============================================
Analyst: Expedition Meteorologist
Target Region: Himalayas / South Asia (Lat: 20°N to 40°N, Lon: 70°E to 95°E)

BACKGROUND
----------
Our expedition team is finalizing the itinerary for an 8000m peak summit attempt. 
Historically, summits are attempted in the pre-monsoon (Spring) or post-monsoon (Autumn) 
windows. We must strictly avoid the massive snow accumulations and avalanche hazards 
brought by the summer monsoon. We are debating between May and July.

DATA REQUIREMENTS
-----------------
Use NASA Panoply to analyze these two datasets:
1. Precipitation: ~/PanoplyData/prate.sfc.mon.ltm.nc
   Variable: prate (Precipitation Rate)
2. Temperature: ~/PanoplyData/air.mon.ltm.nc
   Variable: air (Surface Air Temperature)

CRITICAL INSTRUCTION: REGIONAL BOUNDING
---------------------------------------
Global maps are useless for alpine navigation. You MUST restrict the map bounds 
in Panoply (using the map/projection tab settings) to the Himalayan region 
(Lat: 20 to 40, Lon: 70 to 95) before exporting any plots.

REQUIRED DELIVERABLES (Save to ~/Documents/Expedition/)
-------------------------------------------------------
1. himalaya_precip_may.png
   - Regional precipitation map for May (time index 4)
2. himalaya_precip_july.png
   - Regional precipitation map for July (time index 6)
3. himalaya_temp_may.png
   - Regional surface air temperature map for May
4. summit_report.txt
   - Fill in the following keys exactly as formatted below:

     TARGET_REGION: Himalayas
     PREFERRED_MONTH: [May or July - which is safer from extreme precipitation?]
     AVALANCHE_HAZARD_MONTH: [May or July - which has extreme precipitation?]
     HAZARD_SYSTEM: Indian_Monsoon
     MAY_MOUNTAIN_TEMP_C: [Approximate temperature value in the high Himalayan terrain in CELSIUS, e.g., -15. Note: Check your units!]

Good luck. Lives depend on this climatology assessment.
SPECEOF

chown ga:ga /home/ga/Desktop/expedition_brief.txt
chmod 644 /home/ga/Desktop/expedition_brief.txt

# Kill existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh &"

# Wait for Panoply to start
wait_for_panoply 60
sleep 5

# Focus Panoply window & Maximize
focus_panoply
DISPLAY=:1 wmctrl -r "Panoply" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take an initial screenshot showing the environment setup
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="