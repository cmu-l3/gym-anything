#!/bin/bash
echo "=== Setting up kariba_hydro_seasonality_assessment task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="kariba_hydro_seasonality_assessment"
PRATE_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
AIR_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/KaribaHydro"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify required data files exist
if [ ! -f "$PRATE_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $PRATE_FILE"
    exit 1
fi
if [ ! -f "$AIR_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $AIR_FILE"
    exit 1
fi

echo "Precipitation data file found: $PRATE_FILE ($(stat -c%s "$PRATE_FILE") bytes)"
echo "Air temperature data file found: $AIR_FILE ($(stat -c%s "$AIR_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/wet_season_precip.png"
rm -f "$OUTPUT_DIR/dry_season_precip.png"
rm -f "$OUTPUT_DIR/hydro_planning_report.txt"
rm -f /home/ga/Desktop/kariba_dam_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the task briefing file to the desktop
cat > /home/ga/Desktop/kariba_dam_brief.txt << 'SPECEOF'
ZAMBEZI RIVER AUTHORITY — HYDROLOGICAL PLANNING BRIEF
======================================================
Project ID: ZRA-2024-HYDRO-01
Analyst Role: Hydrological Operations Planner
Priority: HIGH — Rule Curve Revision

BACKGROUND
----------
Lake Kariba, located on the Zambezi River between Zambia and Zimbabwe
(approximate coordinates: 16°S, 28°E), is one of the world's largest
artificial reservoirs by volume. Balancing flood control and hydroelectric
generation requires precise knowledge of the basin's extreme seasonality.
We must update the operational "rule curve" using NCEP long-term mean
climatology. 

DATA REQUIREMENTS
-----------------
You have two datasets available in ~/PanoplyData/:
1. Precipitation Rate (prate.sfc.mon.ltm.nc) - unit: kg/m^2/s
2. Surface Air Temperature (air.mon.ltm.nc) - unit: Kelvin

TOOL: NASA Panoply

REQUIRED ANALYSIS
-----------------
1. PRECIPITATION SEASONALITY:
   Open the precipitation dataset and explore the monthly time steps for the 
   Southern Africa / Zambezi region (around 16°S, 28°E). 
   - Identify the single WETTEST climatological month.
   - Identify the single DRIEST climatological month.

2. TEMPERATURE & EVAPORATION EXTREMES:
   Open the surface air temperature dataset. The highest evaporation rates 
   occur during the pre-monsoon thermal maximum.
   - Explore the time steps to identify the HOTTEST climatological month
     for the Kariba region.
   - Extract the approximate surface air temperature (in Kelvin) over the 
     basin during October.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved exactly to: ~/Documents/KaribaHydro/

1. Wet Season Precipitation Map:
   Filename: wet_season_precip.png
   (Export a geo-mapped plot showing precipitation over Southern Africa 
   during the identified wettest month)

2. Dry Season Precipitation Map:
   Filename: dry_season_precip.png
   (Export a geo-mapped plot showing precipitation over Southern Africa 
   during the identified driest month)

3. Hydro Planning Report:
   Filename: hydro_planning_report.txt
   Required fields (use EXACTLY these key names, one per line):
     BASIN: Zambezi
     WETTEST_MONTH: [Month name, e.g., January]
     DRIEST_MONTH: [Month name, e.g., August]
     HOTTEST_MONTH: [Month name, e.g., November]
     OCTOBER_TEMP_K: [Approximate temperature in Kelvin for October over Kariba, e.g., 299.5]
     EVAPORATION_RISK: HIGH

SUBMISSION: Please complete immediately for the engineering review board.
SPECEOF

chown ga:ga /home/ga/Desktop/kariba_dam_brief.txt
chmod 644 /home/ga/Desktop/kariba_dam_brief.txt
echo "Briefing file written to ~/Desktop/kariba_dam_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with precipitation data pre-loaded
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$PRATE_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Panoply Sources window
focus_panoply
sleep 1

# Capture initial state screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="