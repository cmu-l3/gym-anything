#!/bin/bash
echo "=== Setting up freeze_thaw_infrastructure_risk_assessment task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="freeze_thaw_infrastructure_risk_assessment"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/FreezeThaw"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "Data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory owned by ga
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/temperature_january.png"
rm -f "$OUTPUT_DIR/temperature_march.png"
rm -f "$OUTPUT_DIR/freeze_thaw_report.txt"
rm -f /home/ga/Desktop/freeze_thaw_assessment_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp (anti-gaming)
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the assessment request spec file to the desktop
cat > /home/ga/Desktop/freeze_thaw_assessment_request.txt << 'SPECEOF'
FEDERAL HIGHWAY ADMINISTRATION
Office of Infrastructure Research & Development

MEMORANDUM

TO: Climate Analysis Division
FROM: Director, Pavement Preservation Program
DATE: Spring FY2024
RE: Spring Freeze-Thaw Damage Risk Assessment

OBJECTIVE:
Prepare a climatological assessment of freeze-thaw cycling risk for Northern
Hemisphere transportation infrastructure. This analysis will inform FY2025 spring
maintenance budget allocation across FHWA regional offices.

REQUIRED DELIVERABLES:
All outputs must be saved to: ~/Documents/FreezeThaw/

1. TEMPERATURE MAP — JANUARY (Deep Winter Baseline)
   Export a surface air temperature map for January showing the NH thermal field.
   Save to: ~/Documents/FreezeThaw/temperature_january.png

2. TEMPERATURE MAP — MARCH (Spring Transition)
   Export a surface air temperature map for March showing the spring warming pattern.
   Save to: ~/Documents/FreezeThaw/temperature_march.png

3. FREEZE-THAW RISK ASSESSMENT REPORT
   Save to: ~/Documents/FreezeThaw/freeze_thaw_report.txt

   The report MUST include the following tagged fields (use exact keys):
   - ANALYSIS_MONTHS: [the two months examined, e.g. January, March]
   - FREEZE_THAW_BELT_LAT_RANGE_N: [latitude range in degrees N where March
     mean temperature is near 0°C — this is the zone of maximum freeze-thaw damage]
   - HIGHEST_RISK_CONTINENT: [North_America, Europe, or Asia]
   - RISK_MECHANISM: [must explicitly state 'freeze-thaw cycling']
   - MEAN_TEMP_AT_BELT_C: [the approximate mean temperature within the identified belt in °C]
   - BUDGET_PRIORITY_REGION: [a specific geographic region for priority funding]

DATASET:
   Use the NCEP/NCAR Reanalysis surface air temperature climatology:
   /home/ga/PanoplyData/air.mon.ltm.nc
   Variable: air (surface air temperature in °C)

BACKGROUND:
   Freeze-thaw cycling occurs when temperatures oscillate around 0°C, causing
   water in pavement cracks to repeatedly freeze (expand) and thaw (contract).
   The March 0°C isotherm defines the spring "freeze-thaw belt" where this
   damage mechanism is most active. Compare January (deep winter, when the
   ground is continuously frozen) with March (transition season) to identify
   the northward migration of the freezing line.
SPECEOF

chown ga:ga /home/ga/Desktop/freeze_thaw_assessment_request.txt
chmod 644 /home/ga/Desktop/freeze_thaw_assessment_request.txt
echo "Assessment request spec file written to ~/Desktop/freeze_thaw_assessment_request.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with air temperature data pre-loaded
echo "Launching Panoply with air temperature data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' > /dev/null 2>&1 &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 5

# Maximize and focus Panoply
maximize_panoply
focus_panoply
sleep 2

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="