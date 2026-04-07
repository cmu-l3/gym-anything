#!/bin/bash
echo "=== Setting up arabica_coffee_climatology_validation task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="arabica_coffee_climatology_validation"
OUTPUT_DIR="/home/ga/Documents/CoffeeStudy"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Data files
AIR_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
PRATE_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"

# Verify both data files exist
if [ ! -f "$AIR_FILE" ] || [ ! -f "$PRATE_FILE" ]; then
    echo "ERROR: Required data files not found in /home/ga/PanoplyData/"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "Data files found and verified."

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/minas_temp_cycle.png"
rm -f "$OUTPUT_DIR/minas_precip_cycle.png"
rm -f "$OUTPUT_DIR/minas_precip_timeseries.csv"
rm -f "$OUTPUT_DIR/coffee_baseline_report.txt"
rm -f /home/ga/Desktop/coffee_baseline_mandate.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp (Anti-gaming)
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/coffee_baseline_mandate.txt << 'SPECEOF'
NEUMANN KAFFEE GRUPPE — COMMODITY ANALYSIS DIVISION
AGRONOMIC CLIMATOLOGY BASELINE MANDATE
===================================================
Mandate ID: NKG-2024-BR-092
Analyst Role: Agricultural Commodity Analyst
Region: Minas Gerais, Brazil (Primary Arabica Coffee Belt)

BACKGROUND
----------
Arabica coffee (Coffea arabica) is highly sensitive to climatic conditions.
Optimal growth requires moderate highland temperatures (15-24°C). Furthermore,
Arabica requires a distinct dry season (2-3 months of low precipitation) during
the Southern Hemisphere winter. This dry period stresses the plant and synchronizes
the flowering process so that cherries ripen uniformly when the summer rains return.

You are required to extract the 12-month climatological cycle of temperature and
precipitation for the core Brazilian Arabica belt to validate its agronomic suitability.

DATA REQUIREMENTS
-----------------
- Datasets: ~/PanoplyData/air.mon.ltm.nc (Temperature)
            ~/PanoplyData/prate.sfc.mon.ltm.nc (Precipitation)
- Target Coordinates:
  - Latitude: 20.0°S (-20.0)
  - Longitude: 45.0°W (Note: NCEP data uses 0-360°E longitude. 45°W = 315°E)

REQUIRED ANALYSIS & DELIVERABLES
--------------------------------
All outputs must be saved to: ~/Documents/CoffeeStudy/

1. Temperature Annual Cycle Plot:
   - Create a 1D Line Plot (Create Plot -> "Line plot along Time") for 'air'
   - Set Latitude to -20.0 and Longitude to 315.0
   - Export plot to: minas_temp_cycle.png

2. Precipitation Annual Cycle Plot:
   - Create a 1D Line Plot for 'prate'
   - Set Latitude to -20.0 and Longitude to 315.0
   - Export plot to: minas_precip_cycle.png

3. Precipitation Raw Data Export:
   - From your 1D precipitation plot, export the 12-month data to CSV
   - Export data to: minas_precip_timeseries.csv
   - (Use File > Export Data or similar to export the underlying table)

4. Agronomic Assessment Report:
   - File: coffee_baseline_report.txt
   - Required fields (use EXACTLY these key names, one per line):
     TARGET_LATITUDE: -20
     TARGET_LONGITUDE: 315
     COOLEST_MONTH: [Name the coolest month, e.g., July]
     DRIEST_MONTH: [Name the driest month, e.g., August]
     FLOWERING_SYNC_POTENTIAL: [HIGH if there is a distinct dry winter, LOW otherwise]

SUBMISSION: End of day.
SPECEOF

chown ga:ga /home/ga/Desktop/coffee_baseline_mandate.txt
chmod 644 /home/ga/Desktop/coffee_baseline_mandate.txt
echo "Analysis mandate written to ~/Desktop/coffee_baseline_mandate.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with the air temperature dataset pre-loaded
echo "Launching Panoply with temperature data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$AIR_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 5

# Maximize Panoply Window
maximize_panoply
sleep 2

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png ga
echo "Captured initial screenshot"

echo "=== Task setup complete ==="