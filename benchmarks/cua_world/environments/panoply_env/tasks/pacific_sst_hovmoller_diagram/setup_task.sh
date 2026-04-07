#!/bin/bash
echo "=== Setting up pacific_sst_hovmoller_diagram task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="pacific_sst_hovmoller_diagram"
DATA_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
OUTPUT_DIR="/home/ga/Documents/HovmollerLab"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: SST data file not found: $DATA_FILE"
    exit 1
fi
echo "SST data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/equatorial_sst_hovmoller.png"
rm -f "$OUTPUT_DIR/hovmoller_analysis.txt"
rm -f /home/ga/Desktop/hovmoller_lab_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the lab brief to the desktop
cat > /home/ga/Desktop/hovmoller_lab_brief.txt << 'SPECEOF'
PHYSICAL OCEANOGRAPHY LAB MODULE PREPARATION
=============================================
Module: El Niño-Southern Oscillation (ENSO)
Instructor Role: Physical Oceanography Instructor

BACKGROUND
----------
To introduce students to ENSO, we need a baseline climatological Time-Longitude
plot (Hovmöller diagram) of equatorial sea surface temperatures. This diagram
will allow students to see the permanent Western Pacific Warm Pool and the
seasonal emergence of the Eastern Pacific Cold Tongue in a single graphic.

DATA REQUIREMENTS
-----------------
- Dataset: NOAA OI SST v2 Long-Term Mean (1991-2020)
  File location: ~/PanoplyData/sst.ltm.1991-2020.nc
  Variable: sst (Sea Surface Temperature, degrees Celsius)
- Tool: NASA Panoply

REQUIRED ANALYSIS
-----------------
You must create a 2D Longitude-Time plot. This is a fundamental change from
the default geo-mapped plots in Panoply.

1. Open the SST variable, but instead of a standard Lon-Lat map, create a
   "Longitude-Time" plot (Hovmöller diagram).
2. Because the data is 3D (time, lat, lon) and you are plotting 2D (time, lon),
   you must fix the remaining dimension. Fix the Latitude exactly at the Equator (0°).
3. Export the resulting diagram.
4. Interpret the diagram to answer two scientific questions about the Pacific Basin.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/HovmollerLab/

1. Equatorial SST Hovmöller diagram:
   Filename: equatorial_sst_hovmoller.png
   (Export the plot via File > Save Image As)

2. Hovmöller analysis report:
   Filename: hovmoller_analysis.txt
   Required fields (use EXACTLY these key names, one per line):
     PLOT_DIMENSIONS: [Specify what you plotted, e.g., Longitude-Time]
     LATITUDE_FIXED_VALUE: [The numeric latitude value you sliced at]
     WARMEST_PACIFIC_BASIN: [Which side of the Pacific basin is warmest year-round? East or West?]
     COLDEST_EAST_PACIFIC_MONTH: [In which month does the Eastern Pacific reach its absolute minimum temperature?]

NOTES
-----
- When creating the plot, ensure you select the correct plot type from the Panoply prompt.
- Use the Array(s) panel to set the latitude exactly to 0.0.
SPECEOF

chown ga:ga /home/ga/Desktop/hovmoller_lab_brief.txt
chmod 644 /home/ga/Desktop/hovmoller_lab_brief.txt
echo "Lab brief written to ~/Desktop/hovmoller_lab_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with SST data pre-loaded
echo "Launching Panoply with SST data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 5

# Maximize Panoply Sources window
maximize_panoply

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus the Sources window
focus_panoply
sleep 1

# Take initial screenshot to capture initial setup state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="