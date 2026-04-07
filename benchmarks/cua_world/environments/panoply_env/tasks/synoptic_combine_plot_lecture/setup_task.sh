#!/bin/bash
echo "=== Setting up synoptic_combine_plot_lecture task ==="

TASK_NAME="synoptic_combine_plot_lecture"
AIR_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
SLP_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/SynopticLecture"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify datasets exist
if [ ! -f "$AIR_FILE" ]; then
    echo "ERROR: Air temperature data not found: $AIR_FILE"
    exit 1
fi
if [ ! -f "$SLP_FILE" ]; then
    echo "ERROR: SLP data not found: $SLP_FILE"
    exit 1
fi
echo "Verified datasets present."

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs
rm -f "$OUTPUT_DIR/combine_temp_slp_jan.png"
rm -f "$OUTPUT_DIR/slp_standalone_jan.png"
rm -f "$OUTPUT_DIR/synoptic_teaching_notes.txt"
rm -f /home/ga/Desktop/synoptic_lecture_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the lecture brief to the desktop
cat > /home/ga/Desktop/synoptic_lecture_brief.txt << 'SPECEOF'
ATSC 305: SYNOPTIC METEOROLOGY I — LECTURE PREPARATION
======================================================
Task: Prepare visual aids and teaching notes for the "Semi-Permanent 
Pressure Centers and General Circulation" lecture module.

BACKGROUND
----------
For tomorrow's lecture, I need a visual demonstration of how January's major
semi-permanent pressure systems spatially align with the surface temperature
field. We will use Panoply's "Combine Plot" feature to overlay Sea Level Pressure 
(SLP) contour lines on top of an Air Temperature color-filled map.

DATASETS (Located in ~/PanoplyData/)
------------------------------------
1. Air Temperature: air.mon.ltm.nc (Variable: air)
2. Sea Level Pressure: slp.mon.ltm.nc (Variable: slp)

REQUIRED ACTIONS IN PANOPLY
---------------------------
1. Open both datasets in Panoply.
2. Create a "Combine Plot" using the `air` variable from the first dataset and 
   the `slp` variable from the second dataset.
3. Ensure the time step for BOTH variables in the combine plot is set to January.
4. Export the combined plot as an image.
5. Create a separate, standalone plot of just the SLP variable (also for January)
   and export it as an image.

REQUIRED DELIVERABLES
----------------------
Save all files to: ~/Documents/SynopticLecture/

1. Combined Temperature & SLP Plot:
   Filename: combine_temp_slp_jan.png

2. Standalone SLP Plot:
   Filename: slp_standalone_jan.png

3. Teaching Notes File:
   Filename: synoptic_teaching_notes.txt
   (Must contain EXACTLY these keys, one per line, filled with your analysis):
     COMBINE_VARIABLES: [Name the two variables you overlaid]
     ANALYSIS_MONTH: January
     LOW_PRESSURE_CENTER: [Name one major climatological Low, e.g., Icelandic Low or Aleutian Low]
     LOW_CENTER_SLP_HPA: [Approximate SLP value at the center of that Low in hPa]
     HIGH_PRESSURE_CENTER: [Name one major climatological High, e.g., Siberian High or Azores High]
     HIGH_CENTER_SLP_HPA: [Approximate SLP value at the center of that High in hPa]

NOTE: The Panoply `slp` variable is stored in Pascals (Pa). To report values in hPa,
divide by 100 (e.g., 101300 Pa = 1013 hPa).

Thanks,
Professor H.
SPECEOF

chown ga:ga /home/ga/Desktop/synoptic_lecture_brief.txt
chmod 644 /home/ga/Desktop/synoptic_lecture_brief.txt
echo "Lecture brief written to ~/Desktop/synoptic_lecture_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply empty
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh > /dev/null 2>&1 &"

# Wait for Panoply to start
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "panoply"; then
        break
    fi
    sleep 1
done

# Let Panoply fully load
sleep 5

# Maximize Panoply
DISPLAY=:1 wmctrl -r "Panoply" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Panoply" 2>/dev/null || true

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
echo "Initial screenshot captured."

echo "=== Setup complete ==="