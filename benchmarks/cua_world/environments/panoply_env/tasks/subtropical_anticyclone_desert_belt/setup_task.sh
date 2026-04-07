#!/bin/bash
echo "=== Setting up subtropical_anticyclone_desert_belt task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="subtropical_anticyclone_desert_belt"
SLP_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
PRATE_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/DesertBelt"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data files exist
if [ ! -f "$SLP_FILE" ]; then
    echo "ERROR: SLP data file not found: $SLP_FILE"
    exit 1
fi
if [ ! -f "$PRATE_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $PRATE_FILE"
    exit 1
fi

echo "SLP data file found: $SLP_FILE"
echo "Precipitation data file found: $PRATE_FILE"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/slp_global_july.png"
rm -f "$OUTPUT_DIR/precip_global_july.png"
rm -f "$OUTPUT_DIR/desert_belt_report.txt"
rm -f /home/ga/Desktop/desertification_analysis_mandate.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/desertification_analysis_mandate.txt << 'SPECEOF'
UNEP DIVISION OF EARLY WARNING AND ASSESSMENT
DESERTIFICATION ANALYSIS MANDATE
==================================================
Mandate ID: UNEP-UNCCD-2024-004
Analyst Role: Desertification Researcher
Event: UNCCD COP Preparatory Session

BACKGROUND
----------
The world's great hot deserts (Sahara, Arabian, Sonoran, Atacama, Kalahari, Australian)
all lie within the subtropical belt (roughly 20-35° latitude). This is driven by
the descending branch of the Hadley cell. As air rises at the equator (ITCZ),
it travels poleward and sinks in the subtropics. This large-scale atmospheric
subsidence creates semi-permanent high-pressure systems (subtropical anticyclones)
that suppress convection, dry the atmosphere, and prevent precipitation.

As climate change causes the Hadley cell to expand, these desert belts are
projected to widen, threatening marginal dryland agricultural communities.

DATA REQUIREMENTS
-----------------
We require visual evidence of the physical link between high pressure and
low precipitation for our upcoming presentation.
1. Dataset 1: NCEP Sea Level Pressure (slp.mon.ltm.nc)
2. Dataset 2: NCEP Precipitation Rate (prate.sfc.mon.ltm.nc)
Time Step: July (Index 6)
Tool: NASA Panoply

REQUIRED DELIVERABLES
----------------------
All outputs must be saved exactly to: ~/Documents/DesertBelt/

1. SLP Global Map (July):
   Filename: slp_global_july.png
   (Shows the strong subtropical highs like the Azores High/North Pacific High)

2. Precipitation Global Map (July):
   Filename: precip_global_july.png
   (Shows the lack of rainfall in the same subtropical regions)

3. Desert Belt Assessment Report:
   Filename: desert_belt_report.txt
   Required fields (use EXACTLY these key names, one per line):
     ANALYSIS_MONTH: July
     NH_SUBTROPICAL_HIGH: [Name of a Northern Hemisphere subtropical high]
     ASSOCIATED_DESERT: [Name of a major hot desert linked to this high]
     MECHANISM: [1-2 sentences explaining how subsidence/Hadley cell/sinking air prevents rain]
     SLP_PRECIP_RELATIONSHIP: [NEGATIVE, POSITIVE, or NONE]
       *(Note: Because high pressure prevents rain, the anomaly correlation is inverse)*

SUBMISSION DEADLINE: COB Today
SPECEOF

chown ga:ga /home/ga/Desktop/desertification_analysis_mandate.txt
chmod 644 /home/ga/Desktop/desertification_analysis_mandate.txt
echo "Mandate written to ~/Desktop/desertification_analysis_mandate.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with the SLP data pre-loaded
echo "Launching Panoply with SLP data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$SLP_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 5

# Dismiss startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize Panoply
maximize_panoply

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="