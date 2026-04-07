#!/bin/bash
echo "=== Setting up mascarene_monsoon_pressure_gradient task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="mascarene_monsoon_pressure_gradient"
DATA_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/MaritimeRouting"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: SLP data file not found: $DATA_FILE"
    exit 1
fi
echo "SLP data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs
rm -f "$OUTPUT_DIR/indian_ocean_slp_july.png"
rm -f "$OUTPUT_DIR/monsoon_gradient_report.txt"
rm -f /home/ga/Desktop/routing_climatology_mandate.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp for anti-gaming verification
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/routing_climatology_mandate.txt << 'SPECEOF'
GLOBAL MARITIME ROUTING AGENCY
CLIMATOLOGY UPDATE MANDATE
============================================
Mandate ID: MR-2024-JUL-001
Role: Marine Meteorologist / Routing Analyst
Priority: HIGH — Seasonal Model Calibration

BACKGROUND
----------
During the Northern Hemisphere summer, the intense pressure gradient between the
Southern Indian Ocean and the Asian continent drives the ferocious Southwest Monsoon
(including the Somali Jet). This causes severe sea states (heavy swell > 5m) in the
Arabian Sea, forcing commercial vessels transiting between the Suez Canal and
Singapore to route further south.

We need to update our baseline July climatological pressure differential to
calibrate our seasonal wave-height forecast model.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Long-Term Mean Sea Level Pressure
  File location: ~/PanoplyData/slp.mon.ltm.nc
  Variable: slp (Sea Level Pressure, millibars/hPa)
  Time step: July (the peak monsoon month)
- Tool: NASA Panoply

ANALYSIS PROCEDURE
------------------
1. Create a geo-mapped plot of July Sea Level Pressure.
2. Adjust the map bounds to focus on the Indian Ocean (approx. 40°S to 40°N, 30°E to 100°E).
3. Export the map to the required directory.
4. Using Panoply's Array tab or map tooltip cursor, locate and extract the approximate:
   a) Peak pressure value and coordinates of the Mascarene High (located in the
      southern Indian Ocean, typically 25°S–35°S).
   b) Minimum pressure value and coordinates of the Asian/Monsoon Low (located
      over the Arabian Peninsula / Pakistan, typically 20°N–35°N).
5. Calculate the cross-equatorial pressure gradient:
   Gradient (mb) = Mascarene High (mb) - Monsoon Low (mb)

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/MaritimeRouting/

1. July Indian Ocean SLP Map:
   Filename: indian_ocean_slp_july.png

2. Climatology Report:
   Filename: monsoon_gradient_report.txt
   Required fields (use EXACTLY these key names, one per line):
     ANALYSIS_MONTH: July
     MASCARENE_HIGH_LAT: [Extracted latitude in decimal degrees, negative for South]
     MASCARENE_HIGH_LON: [Extracted longitude in decimal degrees]
     MASCARENE_HIGH_MB: [Peak pressure value in mb]
     MONSOON_LOW_LAT: [Extracted latitude in decimal degrees]
     MONSOON_LOW_LON: [Extracted longitude in decimal degrees]
     MONSOON_LOW_MB: [Minimum pressure value in mb]
     GRADIENT_DELTA_MB: [Calculated difference: High minus Low]
     PRIMARY_MARITIME_HAZARD: Somali Jet / Heavy Swell
SPECEOF

chown ga:ga /home/ga/Desktop/routing_climatology_mandate.txt
chmod 644 /home/ga/Desktop/routing_climatology_mandate.txt
echo "Mandate written to ~/Desktop/routing_climatology_mandate.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with SLP data pre-loaded
echo "Launching Panoply with SLP data..."
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

# Try to double-click the slp variable to start the plot creation flow
DISPLAY=:1 xdotool mousemove 728 530 click --repeat 2 --delay 100 1 2>/dev/null || true
sleep 3
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 8

# Wait for plot and maximize window
sleep 5
maximize_panoply

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task setup complete ==="