#!/bin/bash
echo "=== Setting up ipcc_accessible_climate_visualization task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="ipcc_accessible_climate_visualization"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/IPCC_Report"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $DATA_FILE"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs
rm -f "$OUTPUT_DIR/air_temp_july_accessible.png"
rm -f "$OUTPUT_DIR/visualization_metadata.txt"
rm -f /home/ga/Desktop/ipcc_formatting_guidelines.txt

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis brief to the desktop
cat > /home/ga/Desktop/ipcc_formatting_guidelines.txt << 'SPECEOF'
IPCC SYNTHESIS REPORT — VISUALIZATION FORMATTING GUIDELINES
============================================================
Author Role: Scientific Data Visualizer
Figure: Global Surface Air Temperature (July Climatology)
Priority: HIGH (Accessibility Compliance required before publication)

BACKGROUND
----------
Scientific publishing standards strictly prohibit the use of "rainbow" or "jet"
color scales. These scales are not perceptually uniform and obscure data for 
readers with color vision deficiencies (colorblindness). Furthermore, default
Equirectangular (cylindrical) map projections heavily distort high latitudes, 
and Euro-centric (0° Longitude) maps split the Pacific Ocean in half, obscuring
important global phenomena like ENSO.

You must standardize the raw Panoply visualization to meet IPCC guidelines.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly LTM Air Temperature
  File: ~/PanoplyData/air.mon.ltm.nc
  Variable: air (Monthly Long Term Mean Air Temperature)
  Time Period: July (Index 6)

VISUALIZATION REQUIREMENTS
--------------------------
1. Map Projection: Must be changed from the default "Equirectangular" to "Robinson"
   (to provide a better representation of global areas).
2. Central Longitude: Must be changed from 0° to 180°
   (Pacific-centric view, so the Pacific Ocean is whole in the middle).
3. Color Scale: Must be changed to a perceptually uniform, colorblind-safe scale 
   such as "Viridis", "Cividis", "Plasma", "Magma", or "Inferno".
   DO NOT use the default "CB-Met" or any rainbow variant.

DELIVERABLES
------------
All outputs must be saved to: ~/Documents/IPCC_Report/

1. Standardized Map Plot:
   Filename: air_temp_july_accessible.png
   (Export via File > Save Image As in the Panoply plot window)

2. Compliance Metadata Report:
   Filename: visualization_metadata.txt
   Required fields (use EXACTLY these key names, one per line):
     DATA_VARIABLE: air
     MONTH_ANALYZED: July
     PROJECTION_USED: Robinson
     CENTER_LONGITUDE: 180
     COLOR_SCALE_USED: [Insert the exact name of the perceptually uniform scale you selected]
     ACCESSIBILITY_COMPLIANCE: YES
SPECEOF

chown ga:ga /home/ga/Desktop/ipcc_formatting_guidelines.txt
chmod 644 /home/ga/Desktop/ipcc_formatting_guidelines.txt

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
sleep 3

# Launch Panoply with data pre-loaded
echo "Launching Panoply with air temperature data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 10

# Dismiss startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Maximize the main sources window
maximize_panoply 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="