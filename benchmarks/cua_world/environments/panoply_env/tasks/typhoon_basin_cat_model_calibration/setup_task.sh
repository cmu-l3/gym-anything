#!/bin/bash
echo "=== Setting up typhoon_basin_cat_model_calibration task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="typhoon_basin_cat_model_calibration"
SST_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
SLP_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/CatModel"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data files exist
if [ ! -f "$SST_FILE" ]; then
    echo "ERROR: SST data file not found: $SST_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
if [ ! -f "$SLP_FILE" ]; then
    echo "ERROR: SLP data file not found: $SLP_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi

echo "SST data file found: $SST_FILE ($(stat -c%s "$SST_FILE") bytes)"
echo "SLP data file found: $SLP_FILE ($(stat -c%s "$SLP_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/wp_sst_august.png"
rm -f "$OUTPUT_DIR/wp_slp_august.png"
rm -f "$OUTPUT_DIR/calibration_report.txt"
rm -f /home/ga/Desktop/cat_model_calibration_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the model calibration request to the desktop
cat > /home/ga/Desktop/cat_model_calibration_request.txt << 'SPECEOF'
===============================================================
SWISS RE CATASTROPHE MODELING — ANNUAL MODEL CALIBRATION
Property Cat Treaty Renewals: Asia-Pacific Basin
Analyst Directive: WNP Typhoon Model Boundary Condition Verification
===============================================================

OBJECTIVE:
Verify that the climatological SST and SLP fields used as boundary
conditions in the 2024 Western North Pacific (WNP) typhoon catastrophe 
model are consistent with NOAA/NCEP reanalysis data for the peak 
typhoon month (August).

TASKS:
1. Examine NOAA OI SST v2 climatology (sst.ltm.1991-2020.nc)
   for August in the Western Pacific Main Development Region (MDR)
   (approx. 5°N-25°N, 120°E-170°E).
   - Verify SST exceeds the 26.5°C Palmén genesis threshold
   - Export a spatial plot of the warm pool

2. Examine NCEP sea level pressure climatology (slp.mon.ltm.nc)
   for August in the same region.
   - Identify the monsoonal trough signature
   - Export a spatial plot of the SLP field

3. Produce a model calibration report with the following fields:

   CALIBRATION_BASIN: Western_North_Pacific
   CALIBRATION_MONTH: August
   MDR_PEAK_SST_C: [observed peak SST in the MDR, in °C]
   GENESIS_THRESHOLD_MET: [YES/NO — is MDR SST >= 26.5°C?]
   MONSOON_TROUGH_PRESENT: [YES/NO — is trough visible in SLP?]
   TROUGH_MIN_SLP_HPA: [approximate minimum SLP in MDR, in hPa]
   BASIN_ANNUAL_RISK: [EXTREME/HIGH/MODERATE/LOW]
   PEAK_SEASON: [month range of peak typhoon activity]
   DATA_SOURCES: [list the two datasets used]

SCIENTIFIC GUIDANCE:
- The Palmén (1948) threshold of 26.5°C SST is the minimum
  for sustained tropical cyclogenesis.
- WNP warm pool in August typically shows SST of 28-31°C.
- The monsoonal trough appears as an elongated low-pressure
  zone (~1005-1012 hPa) across the Philippine Sea. Note: NCEP SLP
  data may be in Pascals (1 hPa = 100 Pa).
- The WNP is the world's most active TC basin; if August SST
  exceeds threshold AND trough is present, BASIN_ANNUAL_RISK
  should be classified as HIGH or EXTREME.

OUTPUT LOCATION: ~/Documents/CatModel/
REQUIRED FILENAMES:
  wp_sst_august.png
  wp_slp_august.png
  calibration_report.txt
===============================================================
SPECEOF

chown ga:ga /home/ga/Desktop/cat_model_calibration_request.txt
chmod 644 /home/ga/Desktop/cat_model_calibration_request.txt
echo "Calibration request written to ~/Desktop/cat_model_calibration_request.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with BOTH data files pre-loaded to save initial file-open time
echo "Launching Panoply with SST and SLP data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$SST_FILE' '$SLP_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90

# Let Panoply fully load both files
sleep 15

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Sources window
focus_panoply
sleep 1

# Take an initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Setup complete ==="