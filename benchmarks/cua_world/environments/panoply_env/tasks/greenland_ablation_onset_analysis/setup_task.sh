#!/bin/bash
echo "=== Setting up greenland_ablation_onset_analysis task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="greenland_ablation_onset_analysis"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/GrISMelt"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Temperature data file not found: $DATA_FILE"
    exit 1
fi
echo "Data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory owned by ga
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/greenland_temp_april.png"
rm -f "$OUTPUT_DIR/greenland_temp_july.png"
rm -f "$OUTPUT_DIR/ablation_onset_report.txt"
rm -f /home/ga/Desktop/nsidc_melt_briefing.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis brief to the desktop
cat > /home/ga/Desktop/nsidc_melt_briefing.txt << 'SPECEOF'
NSIDC CRYOSPHERIC MONITORING UNIT — ABLATION ONSET BRIEFING
============================================================
Request ID: NSIDC-2024-GRIS-01
Analyst Role: Glaciologist / Cryospheric Scientist

BACKGROUND
----------
To contextualize recent extreme summer melt events, we need to map the historical
climatological baseline of the Greenland Ice Sheet's (GrIS) ablation zone. We
focus on the transition from the pre-melt season (April) to the peak-melt season
(July). Surface air temperature is our primary proxy for melt conditions. 

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Surface Air Temperature Long-Term Mean
  File location: ~/PanoplyData/air.mon.ltm.nc
  Variable: air (Monthly Long Term Mean Surface Air Temperature, Kelvin)
- Tool: NASA Panoply

ANALYSIS PROCEDURE
------------------
1. Create a geo-mapped plot of the 'air' variable.
2. CRITICAL: The default global equirectangular projection severely distorts
   high latitudes. You MUST change the map projection to a North Polar projection
   (e.g., North Polar Stereographic or Orthographic) and adjust the center/zoom
   to clearly focus on the Greenland Ice Sheet.
3. Identify the glaciological melting point threshold in Kelvin.
4. Export a diagnostic plot for April (time index 3, 0-indexed month 3 = April).
5. Export a diagnostic plot for July (time index 6).
6. Compare the temperature patterns against the melt threshold to assess the
   state of the ice sheet's coastal margins versus its high-altitude interior.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/GrISMelt/

1. April temperature map:
   Filename: greenland_temp_april.png
   (Export via File > Save Image As)

2. July temperature map:
   Filename: greenland_temp_july.png

3. Ablation onset report:
   Filename: ablation_onset_report.txt
   Required fields (use EXACTLY these key names, one per line):
     MELT_THRESHOLD_K: [Enter the melting point of ice in Kelvin, e.g., 273.15]
     APRIL_STATUS: [Is the ice sheet entirely FROZEN or MELTING in April?]
     JULY_MARGIN_STATUS: [Are the coastal margins FROZEN or MELTING in July?]
     JULY_INTERIOR_STATUS: [Is the high-altitude interior FROZEN or MELTING in July?]
SPECEOF

chown ga:ga /home/ga/Desktop/nsidc_melt_briefing.txt
chmod 644 /home/ga/Desktop/nsidc_melt_briefing.txt
echo "Briefing document written to ~/Desktop/nsidc_melt_briefing.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with data pre-loaded
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Panoply Sources window
focus_panoply
sleep 1

# Take an initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="