#!/bin/bash
echo "=== Setting up thermal_inertia_phase_shift task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="thermal_inertia_phase_shift"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/ThermalLecture"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify or download data file
if [ ! -f "$DATA_FILE" ] || [ "$(stat -c%s "$DATA_FILE" 2>/dev/null || echo 0)" -lt 100000 ]; then
    echo "Downloading NCEP Surface Air Temperature data..."
    mkdir -p /home/ga/PanoplyData
    wget -q --timeout=120 \
        "https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis.derived/surface/air.mon.ltm.nc" \
        -O "$DATA_FILE" || true
    
    if [ ! -f "$DATA_FILE" ] || [ "$(stat -c%s "$DATA_FILE" 2>/dev/null || echo 0)" -lt 100000 ]; then
        echo "ERROR: Could not download required air temperature data"
        exit 1
    fi
    chown ga:ga "$DATA_FILE"
fi
echo "Data file ready: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/land_annual_cycle.png"
rm -f "$OUTPUT_DIR/ocean_annual_cycle.png"
rm -f "$OUTPUT_DIR/august_global_map.png"
rm -f "$OUTPUT_DIR/thermal_inertia_report.txt"
rm -f /home/ga/Desktop/lecture_prep_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp (Anti-gaming)
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the lecture prep request to the desktop
cat > /home/ga/Desktop/lecture_prep_request.txt << 'SPECEOF'
UNIVERSITY CLIMATE SCIENCE DEPARTMENT
LECTURE PREPARATION DIRECTIVE
=====================================
Topic: Thermodynamic Properties of the Earth System (Thermal Inertia)
Analyst: Instructional Assistant

BACKGROUND
----------
For next week's lecture on Earth's energy budget, we need to demonstrate how the
differing specific heat capacities of land and ocean create a "phase shift" in
the annual temperature cycle. Continental interiors heat up and cool down quickly,
while oceans have massive thermal inertia, causing their peak summer temperature
to lag behind the land.

You must extract 1-dimensional time-series data from the NCEP climatology to
prove this quantitatively, and export a map to show it spatially.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Surface Air Temperature (Monthly Long-Term Mean)
  File: ~/PanoplyData/air.mon.ltm.nc
  Variable: air (Monthly Long Term Mean Air Temperature)
- Tool: NASA Panoply

REQUIRED WORKFLOW & DELIVERABLES
--------------------------------
All outputs must be saved exactly to: ~/Documents/ThermalLecture/

1. LAND TIME-SERIES PLOT
   - Create a "Line plot along a grid axis" for the 'air' variable.
   - Set the X-axis to Time (to show the annual cycle).
   - Fix the spatial coordinates to: Latitude 45°N, Longitude 260°E (North America).
   - Export this plot as: land_annual_cycle.png

2. OCEAN TIME-SERIES PLOT
   - Create another line plot with Time on the X-axis.
   - Fix the spatial coordinates to: Latitude 45°N, Longitude 190°E (North Pacific Ocean).
   - Export this plot as: ocean_annual_cycle.png

3. SPATIAL MAP (DELAYED PEAK)
   - Create a standard 2D geo-gridded spatial plot of the 'air' variable.
   - Navigate to the month of August (Time index 7), which is when the ocean peaks.
   - Export this plot as: august_global_map.png

4. FINDINGS REPORT
   - Extract the peak temperature values and timing directly from your line plots.
   - Create a file named: thermal_inertia_report.txt
   - It must contain EXACTLY these key-value pairs (one per line):
     
     LAND_TARGET: 45N, 260E
     LAND_PEAK_MONTH: [The name of the month where the land temp peaks]
     LAND_PEAK_TEMP_K: [The max temperature value at the land coordinate. If Panoply shows degC, report degC. If K, report K]
     OCEAN_TARGET: 45N, 190E
     OCEAN_PEAK_MONTH: [The name of the month where the ocean temp peaks]
     OCEAN_PEAK_TEMP_K: [The max temperature value at the ocean coordinate]
     PHASE_SHIFT_MONTHS: [The numerical difference in months between the two peaks]
     PRIMARY_PHYSICAL_MECHANISM: [A 2-3 word phrase explaining this lag, e.g., "specific heat capacity" or "thermal inertia"]

NOTE: When setting coordinates in Panoply's line plot controls, Panoply will automatically snap to the nearest native grid point (e.g., ~44.7°N). Use the values at those snapped points.
SPECEOF

chown ga:ga /home/ga/Desktop/lecture_prep_request.txt
chmod 644 /home/ga/Desktop/lecture_prep_request.txt
echo "Directive written to ~/Desktop/lecture_prep_request.txt"

# Kill existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with data pre-loaded
echo "Launching Panoply with Air Temperature data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 5

# Dismiss startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize the Panoply window
maximize_panoply

# Take initial screenshot showing clean starting state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="