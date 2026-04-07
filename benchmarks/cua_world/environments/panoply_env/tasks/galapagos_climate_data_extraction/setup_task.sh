#!/bin/bash
echo "=== Setting up galapagos_climate_data_extraction task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="galapagos_climate_data_extraction"
OUTPUT_DIR="/home/ga/Documents/Galapagos"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"
AIR_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
PRATE_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"

# Verify datasets exist
for FILE in "$AIR_FILE" "$PRATE_FILE"; do
    if [ ! -f "$FILE" ]; then
        echo "ERROR: Required data file not found: $FILE"
        exit 1
    fi
done
echo "Required data files verified."

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/galapagos_temp.csv"
rm -f "$OUTPUT_DIR/galapagos_precip.csv"
rm -f "$OUTPUT_DIR/climate_summary.txt"
echo "Cleaned up any pre-existing outputs in $OUTPUT_DIR"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write instruction brief to desktop
cat > /home/ga/Desktop/galapagos_extraction_brief.txt << 'SPECEOF'
GALAPAGOS CLIMATE DATA EXTRACTION REQUEST
=========================================
For: Penguin Habitat Modeling Team

We need the 12-month climatological time series for Air Temperature (air) 
and Precipitation Rate (prate) exactly at the Galapagos Islands.

Location: Latitude 0°, Longitude 90°W

Important: The NCEP climate datasets use a 0-360° East longitude format. 
You must convert 90°W to the appropriate 0-360° East value (270°E) to 
extract the correct location in Panoply.

Deliverables required in ~/Documents/Galapagos/:
1. galapagos_temp.csv (Exported from Panoply)
2. galapagos_precip.csv (Exported from Panoply)
3. climate_summary.txt with the following format:
   TARGET_LATITUDE: 0
   TARGET_LONGITUDE: 270
   HOTTEST_MONTH: [Name of month]
   WETTEST_MONTH: [Name of month]
   EXTRACTION_METHOD: Panoply CSV Export
SPECEOF

chown ga:ga /home/ga/Desktop/galapagos_extraction_brief.txt
chmod 644 /home/ga/Desktop/galapagos_extraction_brief.txt

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
sleep 3

# Launch Panoply
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh &"

# Wait for Panoply to start
wait_for_panoply 60
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and Maximize Panoply
focus_panoply
maximize_panoply
sleep 2

# Take initial screenshot to prove starting state
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="