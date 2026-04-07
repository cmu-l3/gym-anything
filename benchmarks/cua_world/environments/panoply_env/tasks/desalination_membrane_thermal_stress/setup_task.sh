#!/bin/bash
echo "=== Setting up desalination_membrane_thermal_stress task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="desalination_membrane_thermal_stress"
DATA_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
OUTPUT_DIR="/home/ga/Documents/Desalination"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: SST data file not found: $DATA_FILE"
    exit 1
fi
echo "SST data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/egypt_coasts_feb.png"
rm -f "$OUTPUT_DIR/egypt_coasts_aug.png"
rm -f "$OUTPUT_DIR/thermal_envelope_report.txt"
rm -f /home/ga/Desktop/ro_plant_design_mandate.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the engineering mandate to the desktop
cat > /home/ga/Desktop/ro_plant_design_mandate.txt << 'SPECEOF'
AQUATECH ENGINEERING - RO DESALINATION PLANT DESIGN
===================================================
Project ID: EGY-DESAL-2024-09
Analyst Role: Civil/Chemical Engineer
Task: RO Membrane Thermal Stress Assessment

BACKGROUND
----------
Our firm is designing two Reverse Osmosis (RO) desalination mega-plants for
the Egyptian government. Plant A will be on the Mediterranean Sea (northern coast).
Plant B will be on the Red Sea (eastern coast). 

RO membrane performance and aging are highly sensitive to feed water temperature.
High temperatures (>30°C) degrade membranes rapidly and require different polymer
selections. Low temperatures (<20°C) increase water viscosity, requiring higher
pressure from Variable Frequency Drive (VFD) pumps.

We need a baseline climatological assessment of the thermal extremes for both
bodies of water to establish the engineering envelope.

DATA REQUIREMENTS
-----------------
- Dataset: NOAA OI SST v2 Long-Term Mean (1991-2020)
  File location: ~/PanoplyData/sst.ltm.1991-2020.nc
  Variable: sst (Sea Surface Temperature, degrees Celsius)
- Tool: NASA Panoply

REQUIRED ANALYSIS
-----------------
Using Panoply, map the SST variable. Zoom the plot to focus on the coastlines
of Egypt (approximately 15°N–35°N, 25°E–40°E).
Extract the approximate sea surface temperatures immediately off the coast of Egypt
in both the Mediterranean Sea and the Red Sea for two specific months:
- February (the annual thermal minimum)
- August (the annual thermal maximum)

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/Desalination/

1. Map export for February (zoomed to Egypt):
   Filename: egypt_coasts_feb.png

2. Map export for August (zoomed to Egypt):
   Filename: egypt_coasts_aug.png

3. Thermal envelope report:
   Filename: thermal_envelope_report.txt
   Required fields (use EXACTLY these key names, one per line):
     MED_FEB_SST: [approximate Mediterranean SST in Feb, °C]
     MED_AUG_SST: [approximate Mediterranean SST in Aug, °C]
     RED_SEA_FEB_SST: [approximate Red Sea SST in Feb, °C]
     RED_SEA_AUG_SST: [approximate Red Sea SST in Aug, °C]
     HIGHEST_PEAK_STRESS: [Red Sea OR Mediterranean — which water body reaches the highest max temp?]

Note: Extract values visually using the colorbar or array tooltips. Ensure values are reported in °C.
SPECEOF

chown ga:ga /home/ga/Desktop/ro_plant_design_mandate.txt
chmod 644 /home/ga/Desktop/ro_plant_design_mandate.txt
echo "Engineering mandate written to ~/Desktop/ro_plant_design_mandate.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with SST data pre-loaded
echo "Launching Panoply with SST data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90

# Let Panoply fully load
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Panoply Sources window
focus_panoply
sleep 1

# Double-click 'sst' to pre-open the plot creation dialog
echo "Selecting 'sst' variable to pre-open a geo-mapped plot..."
DISPLAY=:1 xdotool mousemove 728 530 click --repeat 2 --delay 100 1 2>/dev/null || true
sleep 3

# Press Enter to create the default geo-referenced plot
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 8

# Wait for plot to render
echo "Waiting for SST plot to render..."
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="