#!/bin/bash
echo "=== Setting up nh_winter_circulation_diagnostic task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="nh_winter_circulation_diagnostic"
AIR_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
SLP_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/WMO_Briefing"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify both data files exist
if [ ! -f "$AIR_FILE" ]; then
    echo "ERROR: Air temperature data not found: $AIR_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
if [ ! -f "$SLP_FILE" ]; then
    echo "ERROR: SLP data not found: $SLP_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "Verified both datasets present:"
echo "  Air temp: $AIR_FILE ($(stat -c%s "$AIR_FILE") bytes)"
echo "  SLP:      $SLP_FILE ($(stat -c%s "$SLP_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/nh_circulation_jan.png"
rm -f "$OUTPUT_DIR/zonal_slp_profile.png"
rm -f "$OUTPUT_DIR/circulation_diagnostic.txt"
rm -f /home/ga/Desktop/wmo_briefing_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the briefing request to the desktop
cat > /home/ga/Desktop/wmo_briefing_request.txt << 'SPECEOF'
WMO REGIONAL TRAINING WORKSHOP — WINTER CIRCULATION DIAGNOSTIC
===============================================================
Analyst Role: Synoptic Meteorologist
Workshop: WMO RA VI Regional Training on Hemispheric Circulation Patterns

BACKGROUND
----------
Tomorrow's workshop session covers "Northern Hemisphere Semi-Permanent
Pressure Centers and Their Thermal Origins." Participants need a professional
diagnostic package demonstrating how wintertime continental cooling creates
and sustains the major pressure centers: the Siberian High, the Icelandic
Low, and the Aleutian Low.

The key visualization is a combined overlay of surface air temperature
(color fill) with sea level pressure contour lines, centered on the North
Pole to display the hemispheric pattern.

DATASETS (Located in ~/PanoplyData/)
------------------------------------
1. Air Temperature: air.mon.ltm.nc (Variable: air)
2. Sea Level Pressure: slp.mon.ltm.nc (Variable: slp)
Tool: NASA Panoply

REQUIRED ANALYSIS
-----------------
1. Combined Overlay Map:
   Open BOTH datasets in Panoply. Create a Combine Plot using the air
   variable (color fill) and the slp variable (contour lines). Set both
   variables to the January time step. Then change the map projection to
   North Polar Stereographic and center on latitude 90°N to display the
   full hemispheric winter circulation pattern.
   Export as: ~/Documents/WMO_Briefing/nh_circulation_jan.png

2. Zonal Mean SLP Profile:
   Create a separate 1D Line Plot of the slp variable along the Latitude
   axis. In the Array(s) tab, set the Longitude dimension to "Average"
   (zonal mean) and the Time dimension to January. This reveals the
   meridional pressure belt structure.
   Export as: ~/Documents/WMO_Briefing/zonal_slp_profile.png

3. Diagnostic Report:
   Using Panoply's Array data viewer or precise cursor inspection, extract
   the January SLP values at these three critical pressure center locations:
     - Icelandic Low: approximately 65°N, 340°E
     - Siberian High: approximately 50°N, 90°E
     - Aleutian Low: approximately 50°N, 180°E

   NOTE: Check the units shown in Panoply for the SLP variable. If the values
   are displayed in Pascals (e.g., 101300), divide by 100 to convert to hPa.
   If already in millibars (e.g., 1013), the values are equivalent to hPa
   and no conversion is needed. Report all values in hPa.

   Save the report to: ~/Documents/WMO_Briefing/circulation_diagnostic.txt
   Required fields (use EXACTLY these key names, one per line):
     ANALYSIS_MONTH: January
     ICELANDIC_LOW_SLP_HPA: [extracted SLP value in hPa]
     SIBERIAN_HIGH_SLP_HPA: [extracted SLP value in hPa]
     ALEUTIAN_LOW_SLP_HPA: [extracted SLP value in hPa]
     PRESSURE_CONTRAST_HPA: [Siberian High minus Icelandic Low, in hPa]
     DOMINANT_HIGH_REGION: [Geographic name of the region with highest pressure]

SUBMISSION: Save all files before workshop begins.
SPECEOF

chown ga:ga /home/ga/Desktop/wmo_briefing_request.txt
chmod 644 /home/ga/Desktop/wmo_briefing_request.txt
echo "Briefing request written to ~/Desktop/wmo_briefing_request.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with both datasets pre-loaded
echo "Launching Panoply with both datasets..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$AIR_FILE' '$SLP_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus and maximize Panoply
focus_panoply
maximize_panoply
sleep 2

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
