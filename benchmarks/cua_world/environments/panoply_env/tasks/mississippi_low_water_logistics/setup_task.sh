#!/bin/bash
echo "=== Setting up mississippi_low_water_logistics task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="mississippi_low_water_logistics"
DATA_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/MississippiLogistics"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Data file not found: $DATA_FILE"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/midwest_precip_deficit_may_sep.png"
rm -f "$OUTPUT_DIR/midwest_precip_september.png"
rm -f "$OUTPUT_DIR/draft_restriction_report.txt"
rm -f /home/ga/Desktop/waterway_logistics_brief.txt

# Record task start timestamp (anti-gaming)
echo "$(date +%s)" > "$START_TS_FILE"

# Write the briefing
cat > /home/ga/Desktop/waterway_logistics_brief.txt << 'SPECEOF'
MISSISSIPPI RIVER WATERWAY LOGISTICS
AUTUMN DRAFT RESTRICTION PLANNING BRIEF
======================================================
Analyst Role: Logistics Planning Analyst
Priority: High

BACKGROUND
----------
The Mississippi River system handles ~60% of US agricultural exports, with peak
barge traffic occurring during the autumn harvest season. However, climatologically,
late summer/autumn is the lowest water period for the river, often necessitating
draft restrictions (reducing the cargo weight a barge can carry) or causing groundings.

To prepare for this year's harvest season, we need a climatological baseline
showing the precipitation drop-off between the spring flood season (May) and
the autumn low-water season (September) across the US Midwest watershed.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Long-Term Mean Precipitation Rate
  File: ~/PanoplyData/prate.sfc.mon.ltm.nc
  Variable: prate (Surface Precipitation Rate, kg/m^2/s)
- Tool: NASA Panoply

ANALYSIS PROCEDURE
------------------
1. Difference Plot (Combine Plot):
   In Panoply, select 'prate' and create a "Combine Plot".
   Set Array 1 to May (month index 4).
   Set Array 2 to September (month index 8).
   Configure the plot to show the difference (Array 1 - Array 2).
   Zoom the map view to the US Midwest (approx. 25N to 50N, 105W to 80W).
   Export this plot.

2. Standard Plot:
   Create a regular (non-combine) geo-mapped plot of 'prate' for September only.
   Zoom to the US Midwest.
   Export this plot.

REQUIRED DELIVERABLES
----------------------
Save all files to: ~/Documents/MississippiLogistics/

1. Combine Plot (May - September Difference):
   Filename: midwest_precip_deficit_may_sep.png

2. Standard Plot (September only):
   Filename: midwest_precip_september.png

3. Logistics Report:
   Filename: draft_restriction_report.txt
   Required fields (use EXACTLY these key names, one per line):
     ANALYSIS_MONTHS: May, September
     MAY_WETTER_THAN_SEP: [YES or NO, based on your difference plot where positive means Array 1 > Array 2]
     OPERATIONAL_IMPACT: [1-2 sentences describing the impact of this precipitation trend on autumn barge logistics, using terms like "draft restriction" or "grounding risk"]
SPECEOF

chown ga:ga /home/ga/Desktop/waterway_logistics_brief.txt
chmod 644 /home/ga/Desktop/waterway_logistics_brief.txt

# Launch Panoply
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply window
wait_for_panoply 90
sleep 10

# Dismiss dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

focus_panoply
sleep 1

# Maximize Panoply Sources window to ensure visibility
WID=$(DISPLAY=:1 wmctrl -l | grep -i "panoply" | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="