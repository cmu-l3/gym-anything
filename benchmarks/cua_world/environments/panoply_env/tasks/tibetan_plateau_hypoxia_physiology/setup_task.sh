#!/bin/bash
echo "=== Setting up tibetan_plateau_hypoxia_physiology task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="tibetan_plateau_hypoxia_physiology"
PRES_FILE="/home/ga/PanoplyData/pres.mon.ltm.nc"
SLP_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/HypoxiaStudy"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify required data files exist (both PRES and SLP are needed for the task's trap)
if [ ! -f "$PRES_FILE" ]; then
    echo "ERROR: Surface pressure data file not found: $PRES_FILE"
    exit 1
fi
if [ ! -f "$SLP_FILE" ]; then
    echo "ERROR: Sea level pressure data file not found: $SLP_FILE"
    exit 1
fi

echo "Data files verified: pres.mon.ltm.nc and slp.mon.ltm.nc are present."

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/asia_surface_pressure_july.png"
rm -f "$OUTPUT_DIR/site_selection_report.txt"
rm -f /home/ga/Desktop/physiology_expedition_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis brief to the desktop
cat > /home/ga/Desktop/physiology_expedition_brief.txt << 'SPECEOF'
HIGH-ALTITUDE PHYSIOLOGY EXPEDITION
SITE SELECTION BRIEF
===================================
Project ID: HYPOX-2024-TIBET
Role: Environmental Physiologist
Topic: Chronic Mountain Sickness (Monge's Disease)

BACKGROUND
----------
Our medical research team is planning a large-scale epidemiological study on
physiological adaptations to severe chronic hypoxia. We must locate the largest
inhabited continental region with the lowest ambient atmospheric pressure
during the Northern Hemisphere summer (July).

We know this region is the Tibetan Plateau/Himalayas in the Asian sector.
Your task is to visualize the pressure field over this area and extract the
approximate minimum ambient pressure our field teams will experience.

CRITICAL DATA INSTRUCTION
-------------------------
The climate data repository at `~/PanoplyData/` contains two pressure datasets:
1. `pres.mon.ltm.nc` (Surface Pressure)
2. `slp.mon.ltm.nc` (Sea Level Pressure)

As an environmental physiologist, you must know that Sea Level Pressure is an
artificial mathematical construct corrected to elevation 0. It is USELESS for
determining ambient oxygen availability. You MUST select and analyze the actual
Surface Pressure dataset.

ANALYSIS INSTRUCTIONS
---------------------
1. Open the correct dataset in Panoply.
2. Create a geo-mapped plot of the pressure variable.
3. Navigate the time dimension to July.
4. Zoom/adjust the map bounds to focus on the Asian sector (approx. 10°N–50°N, 60°E–110°E)
   to clearly show the massive pressure deficit over the Tibetan Plateau.
5. Identify the approximate minimum pressure value over the Tibetan Plateau.
6. Note: Panoply displays NCEP pressure data natively in Pascals (Pa).
   The medical community uses hectopascals (hPa) or millibars (mb).
   You must convert your reading from Pascals to hPa (1 hPa = 100 Pa).

REQUIRED DELIVERABLES
----------------------
Deliver all outputs to: ~/Documents/HypoxiaStudy/

1. Asian sector pressure map (July):
   Filename: asia_surface_pressure_july.png

2. Site selection report:
   Filename: site_selection_report.txt
   Required fields (use EXACTLY these key names, one per line):
     TARGET_REGION: Tibetan Plateau
     DATASET_VARIABLE_USED: [pres or slp — write the exact variable name you chose]
     AMBIENT_PRESSURE_HPA: [The minimum pressure you found converted to hPa, e.g. 600]
     PHYSIOLOGICAL_FACTOR: Hypoxia
SPECEOF

chown ga:ga /home/ga/Desktop/physiology_expedition_brief.txt
chmod 644 /home/ga/Desktop/physiology_expedition_brief.txt
echo "Expedition brief written to ~/Desktop/physiology_expedition_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply without pre-loading data so the agent has to explicitly choose
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh &"

# Wait for Panoply to start
wait_for_panoply 60
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus and maximize Panoply window
focus_panoply
maximize_panoply

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="