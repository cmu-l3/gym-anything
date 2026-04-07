#!/bin/bash
echo "=== Setting up siberian_high_cold_surge_diagnostic task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="siberian_high_cold_surge_diagnostic"
DATA_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/ColdSurge"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: SLP data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "SLP data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory owned by ga
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/siberian_high_jan.png"
rm -f "$OUTPUT_DIR/eurasian_slp_july.png"
rm -f "$OUTPUT_DIR/cold_surge_diagnostic.txt"
rm -f /home/ga/Desktop/cold_surge_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate spec file to the desktop
cat > /home/ga/Desktop/cold_surge_brief.txt << 'SPECEOF'
=================================================================
EAST ASIAN WINTER MONSOON - COLD SURGE DIAGNOSTIC BRIEF
Climate Prediction Center / Seasonal Forecast Division
=================================================================

TO:      East Asian Monsoon Desk Analyst
FROM:    Chief, Seasonal Forecast Division
DATE:    Pre-season assessment
SUBJECT: Siberian High Baseline Characterization for Cold Surge Risk

TASK DESCRIPTION:
-----------------
As part of our pre-season preparation for the East Asian Winter Monsoon
(EAWM) forecast cycle, we need an updated baseline characterization of
the Siberian High anticyclone from the NCEP/NCAR reanalysis climatology.

The Siberian High is the dominant surface pressure feature over Eurasia
during boreal winter (DJF). Its intensity and position directly control
the frequency and severity of cold air outbreaks (cold surges) that
propagate southward along the East Asian coast.

REQUIRED DELIVERABLES:
----------------------
1. JANUARY SLP MAP: Export a map of sea level pressure over the Eurasian
   sector (approx. 20N-80N, 30E-150E) for January, clearly showing the
   Siberian High. Save to:
   ~/Documents/ColdSurge/siberian_high_jan.png

2. JULY SLP MAP: Export a matching map for July to demonstrate the
   seasonal contrast (the Siberian High is absent in summer). Save to:
   ~/Documents/ColdSurge/eurasian_slp_july.png

3. DIAGNOSTIC REPORT: Write a structured assessment to:
   ~/Documents/ColdSurge/cold_surge_diagnostic.txt

   The report MUST include these exact fields:
   CENTER_PRESSURE_HPA: [central pressure of the Siberian High in hPa]
   CENTER_LATITUDE: [latitude of the pressure center, degrees N]
   CENTER_LONGITUDE: [longitude of the pressure center, degrees E]
   SEASONAL_CONTRAST: [description of Jan vs Jul difference]
   COLD_SURGE_RISK: [HIGH/MODERATE/LOW based on anticyclone strength]
   ANALYSIS_SEASON: [which season was analyzed]

DATA SOURCE:
------------
NCEP/NCAR Reanalysis Sea Level Pressure Long-Term Mean
File: /home/ga/PanoplyData/slp.mon.ltm.nc
Variable: slp
Time steps: January = first time step, July = 7th time step

NOTE: The SLP data may be stored in Pascals (Pa). To convert to hPa
(millibars), divide by 100. For example, 103500 Pa = 1035.0 hPa.

SCIENTIFIC GUIDANCE:
--------------------
- The Siberian High center is typically located near 50N, 90-100E
- January climatological central pressure: approximately 1035-1040 hPa
- The anticyclone extends from Eastern Europe to the Pacific coast
- Cold surge risk is HIGH when the Siberian High is well-established
  (which it always is in the January climatology)
- In July, the continental interior is dominated by a thermal low
  (the Asian Summer Monsoon's continental heat source)
=================================================================
SPECEOF

chown ga:ga /home/ga/Desktop/cold_surge_brief.txt
chmod 644 /home/ga/Desktop/cold_surge_brief.txt
echo "Forecast brief written to ~/Desktop/cold_surge_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with SLP data pre-loaded
echo "Launching Panoply with SLP data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90

# Let Panoply fully load
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Panoply Sources window
focus_panoply
sleep 1

# Open default map
echo "Selecting 'slp' variable to pre-open a geo-mapped plot..."
DISPLAY=:1 xdotool mousemove 728 530 click --repeat 2 --delay 100 1 2>/dev/null || true
sleep 3
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="