#!/bin/bash
echo "=== Setting up gulfstream_thermal_front_fisheries task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="gulfstream_thermal_front_fisheries"
DATA_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
OUTPUT_DIR="/home/ga/Documents/GulfStream"
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

# Clean up any pre-existing outputs
rm -f "$OUTPUT_DIR/sst_global_feb.png"
rm -f "$OUTPUT_DIR/gulfstream_front_feb.png"
rm -f "$OUTPUT_DIR/thermal_front_report.txt"
rm -f /home/ga/Desktop/gulfstream_habitat_request.txt

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"

# Write the habitat assessment request
cat > /home/ga/Desktop/gulfstream_habitat_request.txt << 'SPECEOF'
NOAA NORTHEAST FISHERIES SCIENCE CENTER
Ecosystem Dynamics & Assessment Branch
Quarterly Habitat Boundary Assessment

TO: Fisheries Oceanography Team
FROM: Dr. Sarah Chen, Branch Chief
RE: Q1 Gulf Stream Thermal Front Position and Intensity

ASSESSMENT REQUEST:

We need to update the winter habitat boundary maps for the
Northwest Atlantic pelagic fishery management zones. Please
use the NOAA OI SST v2 climatology to:

1. Create a global SST overview for February (the month of
   maximum cross-front thermal contrast in the western
   North Atlantic).

2. Create a zoomed plot of the Northwest Atlantic region
   (approximately 25-50°N, 80-50°W) clearly showing the
   Gulf Stream thermal front.

3. Extract SST values from both sides of the front and
   quantify the cross-front temperature gradient.

4. Document the front's approximate latitude and its
   ecological significance for pelagic species habitat.

DATASET: NOAA OI SST v2 Long-Term Mean (1991-2020)
FILE: ~/PanoplyData/sst.ltm.1991-2020.nc

OUTPUT DIRECTORY: ~/Documents/GulfStream/

REQUIRED DELIVERABLES:
- Global SST plot: sst_global_feb.png
- Zoomed front plot: gulfstream_front_feb.png
- Assessment report: thermal_front_report.txt

REPORT FORMAT (use exactly these field labels):
  CURRENT_NAME: [name of the current]
  ANALYSIS_MONTH: [month analyzed]
  WARM_SIDE_SST_C: [SST on the warm/offshore side in °C]
  COLD_SIDE_SST_C: [SST on the cold/shelf side in °C]
  SST_GRADIENT_C: [temperature difference across front in °C]
  FRONT_LATITUDE_N: [approximate latitude of the front axis in °N]
  ECOLOGICAL_SIGNIFICANCE: [brief description of biological importance]

BACKGROUND:
The Gulf Stream's thermal front creates one of the strongest
persistent SST gradients in the world ocean. Pelagic predators
(bluefin tuna, swordfish, mako sharks) concentrate along this
boundary where upwelling and mixing enhance primary productivity.
The front's position and intensity in February establish the
baseline for winter habitat zone definitions used by NAFO and
the Atlantic HMS Management Division.

Please complete by end of day. The data are already installed
in your PanoplyData directory.

- Dr. Chen
SPECEOF

chown ga:ga /home/ga/Desktop/gulfstream_habitat_request.txt
chmod 644 /home/ga/Desktop/gulfstream_habitat_request.txt

# Kill existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with SST data
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 60
sleep 5

# Dismiss startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus Panoply
focus_panoply
sleep 1

# Open default plot
DISPLAY=:1 xdotool mousemove 728 530 click --repeat 2 --delay 100 1 2>/dev/null || true
sleep 3
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 5

take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="