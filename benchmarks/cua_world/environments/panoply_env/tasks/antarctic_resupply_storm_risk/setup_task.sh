#!/bin/bash
echo "=== Setting up antarctic_resupply_storm_risk task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="antarctic_resupply_storm_risk"
DATA_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/AntarcticRoute"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: SLP data file not found: $DATA_FILE"
    exit 1
fi
echo "SLP data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory owned by ga
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/slp_south_polar_july.png"
rm -f "$OUTPUT_DIR/slp_south_polar_january.png"
rm -f "$OUTPUT_DIR/storm_risk_assessment.txt"
rm -f /home/ga/Desktop/antarctic_voyage_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp (anti-gaming)
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the voyage brief to the desktop
cat > /home/ga/Desktop/antarctic_voyage_brief.txt << 'SPECEOF'
=============================================================
AUSTRALIAN ANTARCTIC DIVISION — VOYAGE PLANNING UNIT
RSV Nuyina Seasonal Routing Assessment FY2025
=============================================================

ROUTE: Hobart, Tasmania (42.9°S, 147.3°E) → McMurdo Station (77.8°S, 166.7°E)
TRANSIT DISTANCE: ~3,800 nautical miles
TRANSIT TIME: 7-10 days depending on sea state

ASSESSMENT REQUIREMENT:
The Voyage Planning Unit requires a seasonal storm risk comparison
for the Hobart-McMurdo corridor. Using NCEP/NCAR Reanalysis sea level
pressure (SLP) climatology, compare the Southern Ocean pressure field
between:
  - July (austral winter, expected peak storminess)
  - January (austral summer, expected safest window)

REQUIRED DELIVERABLES:
1. South Polar Stereographic projection SLP map for July
   → Export to: ~/Documents/AntarcticRoute/slp_south_polar_july.png
2. South Polar Stereographic projection SLP map for January
   → Export to: ~/Documents/AntarcticRoute/slp_south_polar_january.png
3. Storm risk assessment report
   → Export to: ~/Documents/AntarcticRoute/storm_risk_assessment.txt

REPORT FORMAT (use these exact field names, one per line):
  ROUTE: Hobart-McMurdo
  TROUGH_LATITUDE_S: [latitude of the circumpolar trough minimum, degrees South, e.g. 63]
  WINTER_TROUGH_SLP_HPA: [minimum mean SLP in the trough belt in July, in hPa]
  SUMMER_TROUGH_SLP_HPA: [minimum mean SLP in the trough belt in January, in hPa]
  SEASONAL_DIFFERENCE_HPA: [summer SLP minus winter SLP]
  STORM_RISK_WINTER: [EXTREME or HIGH]
  STORM_RISK_SUMMER: [MODERATE or LOW]
  RECOMMENDED_TRANSIT_MONTHS: [safest months for transit]
  PROJECTION_USED: [name of projection applied]
  DATA_SOURCE: [dataset filename]

SCIENTIFIC NOTE:
The NCEP SLP dataset stores sea level pressure in Pascals (Pa).
Convert to hectopascals (hPa) by dividing by 100.
Standard sea level pressure: 101325 Pa = 1013.25 hPa.
The circumpolar trough in the Southern Ocean typically shows mean
SLP of 980-995 hPa in winter and 990-1005 hPa in summer.
SPECEOF

chown ga:ga /home/ga/Desktop/antarctic_voyage_brief.txt
chmod 644 /home/ga/Desktop/antarctic_voyage_brief.txt
echo "Voyage brief written to ~/Desktop/antarctic_voyage_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply (Agent must manually open the dataset)
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Maximize Panoply Sources Window
maximize_panoply

# Take initial screenshot to prove starting state
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="