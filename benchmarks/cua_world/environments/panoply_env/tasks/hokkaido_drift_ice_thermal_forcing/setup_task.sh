#!/bin/bash
echo "=== Setting up hokkaido_drift_ice_thermal_forcing task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="hokkaido_drift_ice_thermal_forcing"
AIR_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
SLP_FILE="/home/ga/PanoplyData/slp.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/Ryuhyo"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify required data files exist
for file in "$AIR_FILE" "$SLP_FILE"; do
    if [ ! -f "$file" ]; then
        echo "ERROR: Data file not found: $file"
        ls -la /home/ga/PanoplyData/ 2>/dev/null || true
        exit 1
    fi
    echo "Data file found: $file ($(stat -c%s "$file") bytes)"
done

# Create output directory and set ownership
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/okhotsk_airtemp_feb.png"
rm -f "$OUTPUT_DIR/okhotsk_slp_feb.png"
rm -f "$OUTPUT_DIR/thermal_forcing_report.txt"
rm -f /home/ga/Desktop/ryuhyo_analysis_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp (anti-gaming)
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis brief to the desktop
cat > /home/ga/Desktop/ryuhyo_analysis_brief.txt << 'SPECEOF'
JAPAN COAST GUARD - ICE INFORMATION CENTER
CLIMATOLOGICAL BASELINE ANALYSIS BRIEF
===================================================
Analysis ID: JCG-RYUHYO-2024-02
Analyst Role: Marine Forecaster / Climatologist
Focus Region: East Asia / Sea of Okhotsk (approx. 35°N–65°N, 130°E–160°E)

BACKGROUND
----------
The Sea of Okhotsk is the lowest-latitude sea in the world to experience widespread
seasonal sea ice formation ("Ryuhyo" or drift ice). This ice presents a severe hazard
to maritime navigation around Hokkaido. The ice formation is primarily driven by
intense thermal and dynamic forcing from the Asian continent during the winter.

Specifically, the intense Siberian High pressure system drives deeply sub-freezing
continental polar air mass over the Sea of Okhotsk via strong northwesterly winds.
We require a formal documentation of this February climatological baseline.

DATA REQUIREMENTS
-----------------
- Tool: NASA Panoply
- Air Temperature Dataset: ~/PanoplyData/air.mon.ltm.nc (Variable: air)
- Sea Level Pressure Dataset: ~/PanoplyData/slp.mon.ltm.nc (Variable: slp)
- Time period: February (climatological mean — Time index 1)

REQUIRED ANALYSIS & DELIVERABLES
--------------------------------
You must create two regional plots zoomed to the East Asia / Sea of Okhotsk area
and extract quantitative values for the baseline report.

All outputs must be saved to: ~/Documents/Ryuhyo/

1. Air Temperature Plot (February):
   Filename: okhotsk_airtemp_feb.png
   - Open the air temperature dataset, navigate to February.
   - Zoom the map to East Asia / Sea of Okhotsk.
   - Extract the approximate minimum air temperature over the northern Sea of Okhotsk.
   - Export the plot.

2. Sea Level Pressure Plot (February):
   Filename: okhotsk_slp_feb.png
   - Open the SLP dataset, navigate to February.
   - Zoom to the same region.
   - Identify the approximate central pressure of the Siberian High (the massive
     high-pressure system over mainland Asia/Siberia to the west).
   - Export the plot.

3. Thermal Forcing Report:
   Filename: thermal_forcing_report.txt
   Required fields (use EXACTLY these key names, one per line):
     ANALYSIS_MONTH: February
     REGION: Sea_of_Okhotsk
     MIN_AIR_TEMP_NORTH_OKHOTSK: [extracted minimum temperature, specify C or K]
     SIBERIAN_HIGH_CENTER_SLP_HPA: [extracted central pressure of the Siberian High in hPa]
     INFERRED_WIND: Northwesterly

SUBMISSION: Due before the start of the icebreaker navigation season.
SPECEOF

chown ga:ga /home/ga/Desktop/ryuhyo_analysis_brief.txt
chmod 644 /home/ga/Desktop/ryuhyo_analysis_brief.txt
echo "Analysis brief written to ~/Desktop/ryuhyo_analysis_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with Air Temp data pre-loaded to start the agent's workflow
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$AIR_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Sources window and maximize it
focus_panoply
maximize_panoply

# Take initial screenshot
echo "Capturing initial state..."
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="