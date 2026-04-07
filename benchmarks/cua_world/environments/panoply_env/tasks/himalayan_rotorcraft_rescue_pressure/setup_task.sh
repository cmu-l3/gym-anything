#!/bin/bash
echo "=== Setting up himalayan_rotorcraft_rescue_pressure task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="himalayan_rotorcraft_rescue_pressure"
DATA_DIR="/home/ga/PanoplyData"
OUTPUT_DIR="/home/ga/Documents/HeliSAR"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify required data files exist (we need both pres and slp to exist to present the choice)
if [ ! -f "$DATA_DIR/pres.mon.ltm.nc" ] || [ ! -f "$DATA_DIR/slp.mon.ltm.nc" ]; then
    echo "ERROR: Required pressure datasets not found in $DATA_DIR"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/himalayan_surface_pressure_may.png"
rm -f "$OUTPUT_DIR/pressure_baseline_report.txt"
rm -f /home/ga/Desktop/h145_sar_certification.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis brief to the desktop
cat > /home/ga/Desktop/h145_sar_certification.txt << 'SPECEOF'
AIRBUS HELICOPTERS — HIGH ALTITUDE SAR CERTIFICATION BRIEF
===========================================================
Request ID: H145-SAR-NP-004
Analyst Role: Aviation Aerodynamics Engineer
Target: Nepal / Everest Base Camp Operations

BACKGROUND
----------
We are certifying the H145 helicopter for high-altitude Search and Rescue (SAR)
operations in the Himalayas during the peak spring climbing season. Rotor lift
scales directly with ambient air density, which is governed by the actual
*surface pressure* at the operating altitude, not the idealized sea-level pressure.

To calculate maximum hover payload, we need the baseline climatological ambient
pressure at the Himalayan ridge line (approx. 28°N, 87°E).

DATA REQUIREMENTS
-----------------
- Datasets available: ~/PanoplyData/ (Choose the correct file carefully!)
  *Hint: Aerodynamics depends on the pressure the rotor actually experiences
  at the physical surface altitude, NOT the pressure extrapolated down to sea level.*
- Time period: May (peak Everest climbing season)
- Tool: NASA Panoply

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/HeliSAR/

1. Regional Pressure Map:
   Filename: himalayan_surface_pressure_may.png
   (Export a geo-mapped plot zoomed to the Himalayan/Nepal region)

2. Pressure Baseline Report:
   Filename: pressure_baseline_report.txt
   Required fields (use EXACTLY these key names, one per line):
     TARGET_MONTH: May
     DATASET_USED: [filename of the dataset you selected, e.g., xxx.mon.ltm.nc]
     HIMALAYAN_PRESSURE_PA: [Extract the numeric pressure value in Pascals near 28°N, 87°E. You can use Panoply's cursor tooltip or array viewer.]
     SEA_LEVEL_DIFFERENCE: [Brief 1-sentence note on how this compares to standard sea level pressure]

CRITICAL ENGINEERING WARNING
----------------------------
Using Sea Level Pressure (SLP) for mountain aerodynamics will result in massive
overestimation of lift capacity and catastrophic aircraft failure. Ensure you
are extracting true Surface Pressure.
SPECEOF

chown ga:ga /home/ga/Desktop/h145_sar_certification.txt
chmod 644 /home/ga/Desktop/h145_sar_certification.txt
echo "Certification brief written to ~/Desktop/h145_sar_certification.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply (without pre-loading a file so they have to choose)
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh &"

# Wait for Panoply to start
wait_for_panoply 60
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus Panoply
focus_panoply
maximize_panoply 2>/dev/null || true

# Take an initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="