#!/bin/bash
echo "=== Setting up satellite_rf_rain_fade_analysis task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="satellite_rf_rain_fade_analysis"
DATA_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/RainFade"
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

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/jakarta_precip_timeseries.png"
rm -f "$OUTPUT_DIR/rf_fade_margin_report.txt"
rm -f /home/ga/Desktop/rf_gateway_ticket.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp (anti-gaming)
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the engineering ticket to the desktop
cat > /home/ga/Desktop/rf_gateway_ticket.txt << 'SPECEOF'
STARLINK / VIASAT REGIONAL ENGINEERING
RF GATEWAY DEPLOYMENT — RAIN FADE MARGIN TICKET
================================================
Ticket ID: RF-ENG-2024-JKT-01
Assignee: Satellite RF Systems Engineer
Priority: HIGH — Gateway CDR next week

BACKGROUND
----------
We are finalizing the RF link budget for a new Ka-band/V-band gateway ground 
station to be located near Jakarta, Indonesia (approximate coordinates: 6°S, 106°E).
High-frequency satellite downlinks suffer severe signal attenuation ("rain fade") 
during intense tropical downpours. To maintain our 99.9% SLA uptime, we must 
calculate the required RF transmit power margin based on the peak climatological 
precipitation rate at this location.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Long-Term Mean Precipitation
  File: ~/PanoplyData/prate.sfc.mon.ltm.nc
  Variable: prate (Surface Precipitation Rate, kg/m²/s)
- Tool: NASA Panoply

REQUIRED ANALYSIS
-----------------
Using Panoply, you must:
1. Open the prate dataset.
2. Create a "Line plot of 1D data" (Time-series).
3. Ensure the horizontal axis is 'Time'.
4. Adjust the spatial dimensions (Latitude and Longitude) in the plot controls 
   to the NCEP grid cell closest to Jakarta (near 5.7°S, 106.8°E).
5. Identify the month with the highest precipitation rate.
6. Extract the peak precipitation value for that month.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/RainFade/

1. 1D Time-Series Plot:
   Filename: jakarta_precip_timeseries.png
   (Export the line plot via File > Save Image As)

2. RF Fade Margin Report:
   Filename: rf_fade_margin_report.txt
   Required fields (use EXACTLY these key names, one per line):
     GATEWAY_LOCATION: Jakarta
     GRID_LATITUDE: [The exact NCEP grid latitude you selected, e.g., -5.71]
     GRID_LONGITUDE: [The exact NCEP grid longitude you selected, e.g., 106.87]
     PEAK_RAIN_MONTH: [Name of the wettest month, e.g., January, Feb, etc.]
     PEAK_PRATE_VALUE: [The peak precipitation rate in kg/m^2/s, e.g., 1.5e-4]

NOTE: Panoply displays prate in kg/m^2/s. Use scientific notation or standard 
decimal for the value, but be accurate to at least one significant digit.
SPECEOF

chown ga:ga /home/ga/Desktop/rf_gateway_ticket.txt
chmod 644 /home/ga/Desktop/rf_gateway_ticket.txt
echo "Engineering ticket written to ~/Desktop/rf_gateway_ticket.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with precipitation data pre-loaded
echo "Launching Panoply with precipitation data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90

# Let Panoply fully load the file
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus the Sources window
focus_panoply
sleep 1
maximize_panoply
sleep 1

# Take an initial screenshot proving Panoply is open with the data
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="