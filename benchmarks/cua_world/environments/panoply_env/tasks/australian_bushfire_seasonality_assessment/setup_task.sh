#!/bin/bash
echo "=== Setting up australian_bushfire_seasonality_assessment task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="australian_bushfire_seasonality_assessment"
DATA_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/BushfireRisk"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $DATA_FILE"
    exit 1
fi
echo "Precipitation data file found: $DATA_FILE"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/aus_precip_january.png"
rm -f "$OUTPUT_DIR/aus_precip_august.png"
rm -f "$OUTPUT_DIR/bushfire_seasonality_report.txt"
rm -f /home/ga/Desktop/bushfire_seasonality_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/bushfire_seasonality_brief.txt << 'SPECEOF'
AUSTRALIAN BUREAU OF METEOROLOGY
FIRE CLIMATOLOGY UNIT — SEASONAL BRIEFING
=============================================
Briefing ID: ABOM-FCU-2024-05A
Analyst: Fire Climatologist
Division: National Operations Centre

MANDATE OVERVIEW
----------------
Australia experiences a dramatic seasonal reversal in precipitation that
dictates continental bushfire risk. The tropical North (monsoon savanna) and 
the temperate South (eucalyptus forests) experience their peak fire risks 
at completely opposite times of the year. 

As a fire climatologist, you are required to document this seasonal shift 
using NASA Panoply and climatological precipitation data, and formally 
deduce the peak fire risk month for each region based on the fundamental 
rule of fire meteorology: THE DRIEST SEASON IS THE HIGHEST FIRE RISK.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Surface Gauss Monthly LTM Precipitation Rate
  File: ~/PanoplyData/prate.sfc.mon.ltm.nc
  Variable: prate (Precipitation Rate, kg/m²/s)
  Focus region: Australia (approx. 110°E-155°E, 10°S-45°S)

ANALYSIS PROCEDURE
------------------
1. Open the precipitation dataset in Panoply.
2. Navigate to January (Austral Summer) and zoom the map to focus on Australia.
3. Export the January plot. Observe which coast (North or South) is receiving 
   the heavy monsoon rains, and which coast is dry.
4. Navigate to August (Austral Winter) and update the plot.
5. Export the August plot. Observe how the precipitation has shifted.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved exactly to: ~/Documents/BushfireRisk/

1. January Precipitation Plot:
   Filename: aus_precip_january.png

2. August Precipitation Plot:
   Filename: aus_precip_august.png

3. Seasonal Bushfire Report:
   Filename: bushfire_seasonality_report.txt
   Required fields (use EXACTLY these key names, one per line):
     JANUARY_WET_COAST: [North or South]
     AUGUST_WET_COAST: [North or South]
     NORTHERN_PEAK_FIRE_MONTH: [January or August]
     SOUTHERN_PEAK_FIRE_MONTH: [January or August]

NOTES FOR THE ANALYST
---------------------
- Read the colorbar carefully. Higher prate values = wetter. Lower/zero = drier.
- If a region is WET in a given month, its fire risk is LOW.
- If a region is DRY in a given month, its fire risk is HIGH (peak fire season).
- Use deductive logic to fill out the report accurately based on your visual analysis.
SPECEOF

chown ga:ga /home/ga/Desktop/bushfire_seasonality_brief.txt
chmod 644 /home/ga/Desktop/bushfire_seasonality_brief.txt
echo "Mandate written to ~/Desktop/bushfire_seasonality_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
sleep 3

# Launch Panoply with precipitation data pre-loaded
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 10

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Sources window
focus_panoply
sleep 1

# Capture initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="