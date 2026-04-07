#!/bin/bash
echo "=== Setting up african_itcz_latitudinal_profile task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="african_itcz_latitudinal_profile"
DATA_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/ITCZ_Article"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "Precipitation data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/itcz_jan_profile.png"
rm -f "$OUTPUT_DIR/itcz_jul_profile.png"
rm -f "$OUTPUT_DIR/itcz_migration_report.txt"
rm -f /home/ga/Desktop/journalist_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp (crucial for anti-gaming)
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the brief to the desktop
cat > /home/ga/Desktop/journalist_brief.txt << 'SPECEOF'
SCIENCE MAGAZINE — DATA VISUALIZATION REQUEST
=============================================
Request: 1D Latitudinal Precipitation Profiles (Africa)
Analyst: Data Journalist / Meteorological Visualization Specialist

BACKGROUND
----------
We are publishing a feature on the African Monsoon and the seasonal migration 
of the Intertropical Convergence Zone (ITCZ). Standard 2D maps are too cluttered 
for our layout. We specifically need 1D latitudinal cross-sections cutting straight 
through Central Africa (along the 20°E longitude line) to clearly show the rain 
belt shifting from the southern hemisphere in January to the northern hemisphere 
in July.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Precipitation Rate
  File: ~/PanoplyData/prate.sfc.mon.ltm.nc
  Variable: prate (Surface Precipitation Rate)
- Tool: NASA Panoply

ANALYSIS PROCEDURE
------------------
1. Open the data file in Panoply and select the 'prate' variable.
2. In the "Create Plot" dialog, DO NOT use the default 2D Lon-Lat map. 
   Instead, explicitly choose to create a 1D "Line along Y (Latitude)" plot.
3. In the resulting plot window, set the Longitude dimension to 20°E (or as 
   close as the grid allows).
4. Create one plot with the Time dimension set to January (index 0).
5. Create a second plot with the Time dimension set to July (index 6).
6. Examine the graphs to identify the exact latitude (X-axis) where the 
   precipitation (Y-axis) reaches its absolute peak for each month.

REQUIRED DELIVERABLES
----------------------
Save all outputs to: ~/Documents/ITCZ_Article/

1. January 1D Profile Plot:
   Filename: itcz_jan_profile.png
   (Export using File > Save Image As)

2. July 1D Profile Plot:
   Filename: itcz_jul_profile.png

3. Migration Report:
   Filename: itcz_migration_report.txt
   Required fields (use EXACTLY these key names, one per line):
     JAN_PEAK_LATITUDE: [Numeric latitude of the precipitation peak in January, e.g., -12.5 for 12.5S]
     JUL_PEAK_LATITUDE: [Numeric latitude of the precipitation peak in July, e.g., 8.5 for 8.5N]
     MIGRATION_DIRECTION: [North or South — describing the movement of the peak from Jan to Jul]

NOTE: The prate variable has very small values (e.g., ~10^-5 kg/m^2/s). This is normal. 
Focus on identifying the latitude of the peak on the graph, regardless of the y-axis magnitude.
SPECEOF

chown ga:ga /home/ga/Desktop/journalist_brief.txt
chmod 644 /home/ga/Desktop/journalist_brief.txt
echo "Brief written to ~/Desktop/journalist_brief.txt"

# Kill any existing Panoply instances for clean state
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with data pre-loaded
echo "Launching Panoply with precipitation data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90

# Let Panoply fully load
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Maximize and Focus the Panoply Sources window
focus_panoply
maximize_panoply
sleep 1

# Take an initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="