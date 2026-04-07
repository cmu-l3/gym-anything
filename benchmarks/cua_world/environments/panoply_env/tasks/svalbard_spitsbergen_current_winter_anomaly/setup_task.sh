#!/bin/bash
echo "=== Setting up svalbard_spitsbergen_current_winter_anomaly task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="svalbard_spitsbergen_current_winter_anomaly"
DATA_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
OUTPUT_DIR="/home/ga/Documents/ArcticResearch"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify dataset exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: SST data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "SST data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/arctic_sst_february.png"
rm -f "$OUTPUT_DIR/spitsbergen_anomaly_report.txt"
rm -f /home/ga/Desktop/arctic_anomaly_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis brief to the desktop
cat > /home/ga/Desktop/arctic_anomaly_brief.txt << 'SPECEOF'
NORSK POLARINSTITUTT / NORWEGIAN POLAR INSTITUTE
ARCTIC CLIMATOLOGY BASELINE ASSESSMENT
=================================================
Request ID: NPI-2024-FEB-012
Analyst Role: Arctic Sea Ice Physicist
Priority: NORMAL

BACKGROUND
----------
The waters west of the Svalbard archipelago remain anomalously ice-free even in
deep winter. This is driven by the West Spitsbergen Current—the northernmost
branch of the Atlantic Meridional Overturning Circulation (AMOC) / Gulf Stream
system. To illustrate this immense poleward heat transport, we need a
comparative baseline extraction between Svalbard and the Canadian Arctic
Archipelago at the exact same latitude (~78°N).

DATA REQUIREMENTS
-----------------
- Dataset: NOAA OI SST v2 Long-Term Mean (1991-2020)
  File location: ~/PanoplyData/sst.ltm.1991-2020.nc
  Variable: sst (Sea Surface Temperature, degrees Celsius)
  Time step: February (peak winter sea ice advance)
- Tool: NASA Panoply

REQUIRED ANALYSIS
-----------------
1. Map Projection: Equirectangular maps severely distort the Arctic. You MUST
   change the map projection to a polar view (e.g., North Polar Stereographic
   or North Polar Orthographic) centered on the Arctic Ocean.
2. Comparative Probe:
   - Use Panoply's cursor hover feature to read the SST value in the ocean just
     WEST of Svalbard (approximately 78°N, 5°E to 10°E).
   - Read the SST value in the Canadian Arctic / Baffin Bay at the exact same
     latitude (approximately 78°N, 70°W to 90°W).

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/ArcticResearch/

1. Polar-projected SST map for February:
   Filename: arctic_sst_february.png

2. Formal extraction report:
   Filename: spitsbergen_anomaly_report.txt
   Required fields (use EXACTLY these key names, one per line):
     ANALYSIS_MONTH: February
     PROJECTION_USED: [Name of the polar projection you applied]
     SVALBARD_WEST_SST_C: [Extracted value in °C, e.g., 2.5]
     CANADIAN_ARCTIC_SST_C: [Extracted value in °C, e.g., -1.8]
     WARMING_MECHANISM: [Name of the ocean current responsible for the Svalbard anomaly]
SPECEOF

chown ga:ga /home/ga/Desktop/arctic_anomaly_brief.txt
chmod 644 /home/ga/Desktop/arctic_anomaly_brief.txt
echo "Analysis brief written to ~/Desktop/arctic_anomaly_brief.txt"

# Kill existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with data pre-loaded
echo "Launching Panoply with SST data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 60
sleep 5

# Dismiss dialogs and maximize
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
maximize_panoply 2>/dev/null || true

# Take initial setup screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="