#!/bin/bash
echo "=== Setting up nh_thermal_gradient_dynamics task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="nh_thermal_gradient_dynamics"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $DATA_FILE"
    exit 1
fi
echo "Air temperature data file found: $DATA_FILE"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -rf /home/ga/Documents/ThermalDynamics
rm -f /home/ga/Desktop/thermal_wind_lab.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/thermal_wind_lab.txt << 'SPECEOF'
ATSC 305: SYNOPTIC METEOROLOGY I
LAB PREPARATION INSTRUCTIONS — THERMAL WIND RELATIONSHIP
==========================================================
Instructor: Atmospheric Dynamics Teaching Assistant

BACKGROUND
----------
The Thermal Wind relationship dictates that the vertical wind shear (and thus the strength of the upper-level jet stream) is directly proportional to the horizontal temperature gradient. The intense winter temperature difference between the warm equator and the cold North Pole drives a much stronger jet stream in winter than in summer.

You need to prepare the answer key for this week's lab by extracting the exact Equator-to-Pole temperature gradient magnitude (ΔT) for January and July.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Surface Air Temperature
  File: ~/PanoplyData/air.mon.ltm.nc
  Variable: air (Monthly Long-Term Mean Air Temperature, degC)
- Tool: NASA Panoply

REQUIRED ANALYSIS
-----------------
Using Panoply:
1. Create a 1D Line Plot of air temperature along the Latitude dimension.
2. Crucially, set the Longitude dimension to "Average" (not a single slice) to create a true zonal mean profile.
3. For January (Month Index 0), read the temperature at the Equator (0° Lat) and the North Pole (90°N Lat). Calculate the magnitude of the difference (ΔT). Export the plot.
4. For July (Month Index 6), read the temperatures at the Equator and North Pole. Calculate ΔT. Export the plot.

REQUIRED DELIVERABLES
----------------------
First, create the directory: ~/Documents/ThermalDynamics/

All outputs must be saved to this directory:

1. Zonal mean temperature plot (January):
   Filename: zonal_temp_jan.png

2. Zonal mean temperature plot (July):
   Filename: zonal_temp_jul.png

3. Gradient report:
   Filename: gradient_report.txt
   Required fields (use EXACTLY these key names, one per line):
     JAN_GRADIENT_MAGNITUDE: [The calculated Equator-to-Pole ΔT for January, e.g., 55.4]
     JUL_GRADIENT_MAGNITUDE: [The calculated Equator-to-Pole ΔT for July]
     STRONGER_JET_MONTH: [January or July - which month has the stronger thermal gradient?]
SPECEOF

chown ga:ga /home/ga/Desktop/thermal_wind_lab.txt
chmod 644 /home/ga/Desktop/thermal_wind_lab.txt

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with data pre-loaded
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply window to appear
wait_for_panoply 60
sleep 8

# Maximize and Focus
maximize_panoply
focus_panoply
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="