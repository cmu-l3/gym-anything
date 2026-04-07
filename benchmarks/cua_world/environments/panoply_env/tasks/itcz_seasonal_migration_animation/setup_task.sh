#!/bin/bash
echo "=== Setting up itcz_seasonal_migration_animation task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="itcz_seasonal_migration_animation"
DATA_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/ITCZ_Lesson"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $DATA_FILE"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs
rm -f "$OUTPUT_DIR"/itcz_animation.*
rm -f "$OUTPUT_DIR/lesson_plan.txt"
rm -f /home/ga/Desktop/exhibit_design_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the design brief to the desktop
cat > /home/ga/Desktop/exhibit_design_brief.txt << 'SPECEOF'
EARTH SCIENCE EXHIBIT DESIGN BRIEF
===================================
Project: Global Atmospheric Circulation Interactive
Role: Curriculum Developer / Data Visualizer
Deliverable: ITCZ Seasonal Migration Animation and Lesson Plan

BACKGROUND
----------
The Intertropical Convergence Zone (ITCZ) is a persistent band of low pressure
and heavy precipitation near the equator where the northeast and southeast trade
winds converge. It does not stay perfectly stationary; it migrates north during
the boreal (Northern Hemisphere) summer and south during the austral (Southern
Hemisphere) summer, tracking the zone of maximum solar heating.

We need a looping animation of this precipitation band over a 12-month
climatological cycle to help high school students visualize this movement.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Long-Term Mean Precipitation Rate
  File: ~/PanoplyData/prate.sfc.mon.ltm.nc
  Variable: prate (Surface Precipitation Rate, kg/m²/s)
- Tool: NASA Panoply

REQUIRED WORKFLOW
-----------------
1. Open the precipitation dataset in Panoply.
2. Create a global geo-gridded map plot of the "prate" variable.
3. Use Panoply's built-in "Export Animation" feature (File > Export Animation)
   to create a multimedia file looping over the 12-month 'time' dimension.
   *Note: An Animated GIF or MP4/AVI is acceptable.*
4. Observe the animation to determine the months when the ITCZ reaches its
   absolute northernmost and southernmost latitudinal extremes.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/ITCZ_Lesson/

1. Precipitation Animation File:
   Filename: itcz_animation.gif (or .mp4 / .avi depending on your export format)

2. Exhibit Lesson Plan:
   Filename: lesson_plan.txt
   Required fields (use EXACTLY these key names, one per line):
     TARGET_AUDIENCE: High School Earth Science
     VARIABLE_USED: prate
     ANIMATION_FRAMES: 12
     NORTHERN_PEAK_MONTH: [Identify the month when ITCZ is furthest north]
     SOUTHERN_PEAK_MONTH: [Identify the month when ITCZ is furthest south]
     EQUATORIAL_CROSSING: [Brief 1-sentence description of the ITCZ passing the equator]
SPECEOF

chown ga:ga /home/ga/Desktop/exhibit_design_brief.txt
chmod 644 /home/ga/Desktop/exhibit_design_brief.txt

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
sleep 3

# Launch Panoply
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Panoply"; then
        echo "Panoply window detected"
        break
    fi
    sleep 1
done

sleep 5

# Maximize Panoply
DISPLAY=:1 wmctrl -r "Panoply" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true # Dismiss splash/tips
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="