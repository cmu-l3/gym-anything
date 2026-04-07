#!/bin/bash
echo "=== Setting up naval_asw_sonar_thermal_amplitude task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="naval_asw_sonar_thermal_amplitude"
DATA_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
OUTPUT_DIR="/home/ga/Documents/ASWOceanography"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: SST data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "SST data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/sst_amplitude_aug_feb.png"
rm -f "$OUTPUT_DIR/thermal_amplitude_report.txt"
rm -f /home/ga/Desktop/asw_thermal_mandate.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the mandate file to the desktop
cat > /home/ga/Desktop/asw_thermal_mandate.txt << 'SPECEOF'
NAVAL OCEANOGRAPHIC OFFICE (NAVOCEANO)
ANTI-SUBMARINE WARFARE (ASW) - ENVIRONMENTAL INTELLIGENCE MANDATE
===================================================================
Mandate ID: NAV-ASW-2026-003
Analyst Role: ASW Oceanographer
Priority: HIGH - Fleet deployment planning

BACKGROUND
----------
Sonar detection ranges are highly sensitive to the temperature structure of the
water column. Regions with massive seasonal Sea Surface Temperature (SST) swings
experience drastic changes in acoustic propagation (e.g., shifting from strong
surface ducting in winter to severe downward refraction in summer).

Your task is to identify the Northern Hemisphere maritime regions that experience
the most extreme seasonal SST shifts (thermal amplitude). This is a critical
preparatory step for acoustic modeling.

DATA REQUIREMENTS
-----------------
- Dataset: NOAA OI SST v2 Long-Term Mean (1991-2020)
  File location: ~/PanoplyData/sst.ltm.1991-2020.nc
  Variable: sst (Sea Surface Temperature, degrees Celsius)
- Tool: NASA Panoply

ANALYSIS PROCEDURE
------------------
1. Open the SST dataset in Panoply and create a geo-mapped plot.
2. We need the difference between Northern Hemisphere summer peak and winter minimum.
   Use Panoply's array buffers to configure Array 1 and Array 2.
   Set Array 1 to August and Array 2 to February.
3. Change the plot display to show the mathematical difference: Array 1 - Array 2.
4. Adjust the color scale (Min/Max) to clearly highlight the regions with the
   greatest thermal differences (deltas).
5. Locate the Northern Hemisphere region with the maximum seasonal amplitude
   (the largest delta in °C).

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/ASWOceanography/

1. Seasonal Amplitude Difference Map:
   Filename: sst_amplitude_aug_feb.png
   (Export the difference plot using File > Save Image As)

2. Thermal Amplitude Report:
   Filename: thermal_amplitude_report.txt
   Required fields (use EXACTLY these key names, one per line):
     ASSESSMENT_TYPE: Seasonal_Amplitude
     MONTH_1: August
     MONTH_2: February
     MAX_AMPLITUDE_C: [numeric value of the maximum difference in degrees C]
     PEAK_REGION: [Geographic name of the region with the highest delta]
     TACTICAL_IMPACT: [1-2 sentences on how extreme thermal shifts affect sonar]
SPECEOF

chown ga:ga /home/ga/Desktop/asw_thermal_mandate.txt
chmod 644 /home/ga/Desktop/asw_thermal_mandate.txt
echo "Mandate file written to ~/Desktop/asw_thermal_mandate.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with SST data pre-loaded
echo "Launching Panoply with SST data..."
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

# Open default map plot
DISPLAY=:1 xdotool mousemove 728 530 click --repeat 2 --delay 100 1 2>/dev/null || true
sleep 3
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 8

echo "=== Task setup complete ==="