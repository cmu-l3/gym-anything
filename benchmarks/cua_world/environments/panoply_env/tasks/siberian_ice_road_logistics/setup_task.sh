#!/bin/bash
echo "=== Setting up siberian_ice_road_logistics task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="siberian_ice_road_logistics"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/IceRoads"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "Data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/yakutia_jan_map.png"
rm -f "$OUTPUT_DIR/yakutsk_annual_profile.png"
rm -f "$OUTPUT_DIR/safe_transit_report.txt"
rm -f /home/ga/Desktop/ice_road_logistics_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the logistics request to the desktop
cat > /home/ga/Desktop/ice_road_logistics_request.txt << 'SPECEOF'
SIBERIAN ICE ROAD LOGISTICS PLANNING
====================================
Request ID: LOG-YAK-2026-001
Analyst Role: Logistics Planner
Project: Heavy Machinery Transport (80-ton convoy)

BACKGROUND
----------
We are scheduling the transport of heavy mining equipment across the Lena River
ice roads near Yakutsk, Russia. To support the 80-ton loads, the ice must be
deep-frozen. Engineering constraints mandate that heavy transit is ONLY safe
during months where the climatological mean air temperature is below -20°C.

You need to analyze the NCEP long-term mean air temperature dataset to establish
the safe operating window and provide visual documentation for the insurers.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Long-Term Mean
- File: ~/PanoplyData/air.mon.ltm.nc
- Variable: air (Monthly Mean Air Temperature, Kelvin)
- Location: Yakutsk, Siberia (approximate coordinates: 62.5°N, 130.0°E)
- Tool: NASA Panoply

THERMAL THRESHOLD
-----------------
- Safe operating threshold: -20°C
- IMPORTANT: The NCEP dataset is in Kelvin.
  Threshold in Kelvin = 253.15 K

REQUIRED WORKFLOW
-----------------
1. Create a 2D geographic map of January air temperature (time index 0)
   zoomed in on Eastern Siberia to visualize the winter cold pool.
   Export to: ~/Documents/IceRoads/yakutia_jan_map.png

2. Create a 1D Line Plot (time-series) for the 'air' variable showing the
   annual temperature cycle exactly at Yakutsk (Lat: ~62.5°N, Lon: ~130.0°E).
   (In Panoply, when creating a plot, select "Create 1D Line plot" and set
   the X-axis to time, fixing Lat and Lon at the target coordinates).
   Export to: ~/Documents/IceRoads/yakutsk_annual_profile.png

3. Write a logistics report detailing the safe transit window based on
   your findings from the data.

REQUIRED DELIVERABLES
----------------------
Filename: ~/Documents/IceRoads/safe_transit_report.txt
Required fields (use EXACTLY these key names, one per line):
  LOCATION: Yakutsk
  THRESHOLD_K: 253.15
  SAFE_MONTHS: [Comma-separated list of months where temp < 253.15 K, e.g., Jan, Feb]
  JAN_MIN_TEMP_K: [The actual average temperature reading for January at Yakutsk in Kelvin]
SPECEOF

chown ga:ga /home/ga/Desktop/ice_road_logistics_request.txt
chmod 644 /home/ga/Desktop/ice_road_logistics_request.txt
echo "Logistics request written to ~/Desktop/ice_road_logistics_request.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with data pre-loaded
echo "Launching Panoply with air temperature data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Sources window
focus_panoply
sleep 1

echo "=== Task Setup Complete ==="