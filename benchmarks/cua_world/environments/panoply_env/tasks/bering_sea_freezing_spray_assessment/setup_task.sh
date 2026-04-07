#!/bin/bash
echo "=== Setting up bering_sea_freezing_spray_assessment task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="bering_sea_freezing_spray_assessment"
SST_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
AIR_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/MaritimeSafety"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data files exist
if [ ! -f "$SST_FILE" ]; then
    echo "ERROR: SST data file not found: $SST_FILE"
    exit 1
fi
if [ ! -f "$AIR_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $AIR_FILE"
    exit 1
fi

echo "Data files found."

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/bering_sst_jan.png"
rm -f "$OUTPUT_DIR/bering_airtemp_jan.png"
rm -f "$OUTPUT_DIR/icing_risk_report.txt"
rm -f /home/ga/Desktop/uscg_safety_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the safety brief to the desktop
cat > /home/ga/Desktop/uscg_safety_brief.txt << 'SPECEOF'
USCG DISTRICT 17 (ALASKA) — MARITIME SAFETY BRIEF REQUEST
==========================================================
Request ID: USCG-D17-2024-JAN-FS01
Analyst Role: Maritime Safety Analyst
Priority: ROUTINE — Winter Season Preparation

BACKGROUND
----------
The winter commercial fishing season (e.g., Opilio Crab) in the Bering Sea is
approaching. A major hazard to vessel stability is "superstructure icing"
(freezing spray). This occurs when deeply sub-freezing air masses blow over
unfrozen open water, causing ocean spray to freeze instantly upon contact with
vessel superstructures.

We need a climatological assessment to demonstrate this hazard zone to the fleet.

DATA REQUIREMENTS
-----------------
- Dataset 1 (Ocean): NOAA OI SST v2 Long-Term Mean
  File: ~/PanoplyData/sst.ltm.1991-2020.nc
  Variable: sst (Sea Surface Temperature, °C)

- Dataset 2 (Atmosphere): NCEP/NCAR Reanalysis Surface Air Temperature
  File: ~/PanoplyData/air.mon.ltm.nc
  Variable: air (Surface Air Temperature, typically in Kelvin)

- Time step: January (peak winter)
- Focus Region: Bering Sea and Gulf of Alaska (approx 45°N to 70°N, 160°E to 130°W)
- Tool: NASA Panoply

REQUIRED ANALYSIS
-----------------
1. Export a zoomed plot of the January Sea Surface Temperature for the Bering Sea.
2. Export a zoomed plot of the January Surface Air Temperature for the Bering Sea.
3. Write a safety report estimating the central open-water Bering Sea temperatures.

CRITICAL REQUIREMENT: Unit Conversion
The NCEP air temperature data is typically provided in Kelvin (K). The USCG fleet
operates using Celsius (°C). You MUST convert the air temperature to Celsius in
your final report ( °C = K - 273.15 ).

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/MaritimeSafety/

1. Bering Sea SST Map (January):
   Filename: bering_sst_jan.png

2. Bering Sea Air Temp Map (January):
   Filename: bering_airtemp_jan.png

3. Icing Risk Report:
   Filename: icing_risk_report.txt
   Required exact format:
     TARGET_BASIN: Bering Sea
     ANALYSIS_MONTH: January
     APPROX_AIR_TEMP_C: [Your estimate of central Bering Sea air temp in °C]
     APPROX_SST_C: [Your estimate of central Bering Sea water temp in °C]
     HAZARD_TYPE: Freezing Spray
     RISK_LEVEL: HIGH
SPECEOF

chown ga:ga /home/ga/Desktop/uscg_safety_brief.txt
chmod 644 /home/ga/Desktop/uscg_safety_brief.txt
echo "Safety brief written to ~/Desktop/uscg_safety_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with SST data pre-loaded
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

focus_panoply
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="