#!/bin/bash
echo "=== Setting up continentality_index_array_math task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="continentality_index_array_math"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/Continentality"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "Air temp data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory owned by ga
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/annual_temp_range.png"
rm -f "$OUTPUT_DIR/biome_report.txt"
rm -f /home/ga/Desktop/continentality_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the briefing document to the desktop
cat > /home/ga/Desktop/continentality_brief.txt << 'SPECEOF'
MACROECOLOGY RESEARCH UNIT — CONTINENTALITY INDEX BRIEF
=======================================================
Request ID: ECO-2024-BIOME-004
Role: Climatological Data Analyst
Project: Global Plant Hardiness Zones Mapping

BACKGROUND
----------
The primary limiting factor for many boreal and temperate tree species is
"continentality" — the difference between the warmest and coldest months.
Regions with extreme continentality (massive seasonal temperature swings)
restrict the survival of temperate broadleaf species and favor specialized
boreal conifers like Larix (larch).

We need a global map of the Annual Temperature Range to identify these
extreme regions. This requires mathematically subtracting the January
temperature array from the July temperature array.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Long-Term Mean
  File: ~/PanoplyData/air.mon.ltm.nc
  Variable: air (Surface Air Temperature)
- Tool: NASA Panoply

ANALYSIS PROCEDURE
------------------
1. Open the air.mon.ltm.nc dataset in Panoply.
2. Select the 'air' variable and click "Combine Plot".
3. When prompted, select the 'air' variable again for the second array.
4. In the plot window, configure the tabs:
   - Array 1: Set time to July
   - Array 2: Set time to January
   - Combine: Change the display from "Overlay 1 and 2" to the mathematical
     difference "Array 1 - 2" (this subtracts January from July).
5. Ensure the resulting map clearly shows positive values (huge differences) over
   the Northern Hemisphere landmasses.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/Continentality/

1. Continentality Difference Map:
   Filename: annual_temp_range.png
   (Export via File > Save Image As in the Panoply plot window)

2. Continentality Extrema Report:
   Filename: biome_report.txt
   Required fields (use EXACTLY these key names, one per line):
     OPERATION_USED: [What mathematical operation did you use in the Combine tab?]
     MAX_RANGE_REGION: [Geographic name of the region with the highest positive continentality]
     MAX_RANGE_VALUE: [Approximate value of the maximum temperature difference in this region]

NOTES
-----
- Temperature differences (Delta T) are identical whether viewed in Celsius or Kelvin
  (e.g., an increase of 40K is exactly an increase of 40°C). You may report the value
  directly as shown on the scale.
SPECEOF

chown ga:ga /home/ga/Desktop/continentality_brief.txt
chmod 644 /home/ga/Desktop/continentality_brief.txt
echo "Briefing document written to ~/Desktop/continentality_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with data pre-loaded
echo "Launching Panoply with air temperature data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "panoply"; then
        echo "Panoply window detected after ${i}s"
        break
    fi
    sleep 2
done

# Let Panoply fully initialize
sleep 8

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize and Focus Panoply
PANOPLY_WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "panoply" | head -1 | awk '{print $1}')
if [ -n "$PANOPLY_WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$PANOPLY_WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$PANOPLY_WID" 2>/dev/null || true
fi

sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="