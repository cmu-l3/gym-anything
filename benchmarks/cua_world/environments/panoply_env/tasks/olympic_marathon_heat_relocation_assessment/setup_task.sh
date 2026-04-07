#!/bin/bash
echo "=== Setting up olympic_marathon_heat_relocation_assessment task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="olympic_marathon_heat_relocation_assessment"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/OlympicPlanning"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "Air temperature data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/japan_august_temp.png"
rm -f "$OUTPUT_DIR/marathon_relocation_audit.txt"
rm -f /home/ga/Desktop/ioc_marathon_audit_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/ioc_marathon_audit_request.txt << 'SPECEOF'
INTERNATIONAL OLYMPIC COMMITTEE — MEDICAL & SCIENTIFIC COMMISSION
MARATHON RELOCATION AUDIT REQUEST
==================================================================
Audit ID: IOC-2024-MED-042
Analyst Role: Sports Medical Climatologist
Focus: 2020 Tokyo Olympic Marathon Relocation to Sapporo

BACKGROUND
----------
To protect athletes from extreme heat, the IOC controversially relocated the
2020 Olympic marathon from the host city (Tokyo) 800 km north to Sapporo.
The Medical & Scientific Commission requires a climatological audit to
validate this decision using historical baseline data.

You must extract the exact August mean temperature for both cities from
the NCEP long-term mean dataset and verify the degree of cooling achieved.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Long-Term Mean
  File: ~/PanoplyData/air.mon.ltm.nc
  Variable: air (Surface Air Temperature)
  Time step: August
- Tool: NASA Panoply

TARGET COORDINATES
------------------
- Tokyo grid cell: 35.0°N, 140.0°E
- Sapporo grid cell: 42.5°N, 140.0°E

(Note: NCEP data is on a 2.5-degree grid. These coordinates fall EXACTLY
on the cell centers. You can use Panoply's "Array" tab or the tooltip probe
to extract the exact numerical values.)

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/OlympicPlanning/

1. Regional Temperature Map:
   Filename: japan_august_temp.png
   (Create a geo-mapped plot of the 'air' variable for August. Adjust the
    plot projection/bounds to focus specifically on Japan: approx. 25-50°N,
    125-150°E. Export via File > Save Image As)

2. Decision Audit Report:
   Filename: marathon_relocation_audit.txt
   Required fields (use EXACTLY these key names, one per line):
     ASSESSMENT_MONTH: August
     TOKYO_GRID_TEMP_C: [Extracted NCEP array value for Tokyo in °C]
     SAPPORO_GRID_TEMP_C: [Extracted NCEP array value for Sapporo in °C]
     TEMP_DIFFERENCE_C: [Tokyo temp minus Sapporo temp]
     MEDICAL_CONCLUSION: [Write VALID if difference > 0, INVALID if < 0]

NOTES FOR THE ANALYST
---------------------
- If the Panoply array displays data in Kelvin, you MUST convert your
  final reported values to Celsius (C = K - 273.15).
- Do NOT use Google or external knowledge to fill in real-world averages.
  The audit requires the exact values from the provided NCEP grid.
SPECEOF

chown ga:ga /home/ga/Desktop/ioc_marathon_audit_request.txt
chmod 644 /home/ga/Desktop/ioc_marathon_audit_request.txt
echo "Audit mandate written to ~/Desktop/ioc_marathon_audit_request.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with air temp data pre-loaded
echo "Launching Panoply with air temperature data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90

# Let Panoply fully load
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Sources window
focus_panoply
sleep 1

# Select the 'air' variable in the Sources window (approx location)
DISPLAY=:1 xdotool mousemove 728 530 click --repeat 2 --delay 100 1 2>/dev/null || true
sleep 3

# Press Enter to create the default geo-mapped plot
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 8

# Take initial screenshot of the starting state
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured: $(stat -c %s /tmp/task_initial.png) bytes"
fi

echo "=== Task setup complete ==="