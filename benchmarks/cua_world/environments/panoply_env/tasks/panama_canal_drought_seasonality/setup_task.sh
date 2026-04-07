#!/bin/bash
echo "=== Setting up panama_canal_drought_seasonality task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="panama_canal_drought_seasonality"
DATA_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/CanalAssessment"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $DATA_FILE"
    exit 1
fi
echo "Precipitation data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/annual_precip_profile.png"
rm -f "$OUTPUT_DIR/panama_precip_march.png"
rm -f "$OUTPUT_DIR/panama_precip_october.png"
rm -f "$OUTPUT_DIR/draft_restriction_report.txt"
rm -f /home/ga/Desktop/canal_assessment_brief.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
date +%s > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis brief to the desktop
cat > /home/ga/Desktop/canal_assessment_brief.txt << 'SPECEOF'
MARITIME LOGISTICS OPERATIONS — PANAMA CANAL ASSESSMENT BRIEF
=============================================================
Request ID: ML-2024-PC-009
Analyst Role: Maritime Climate Risk Analyst
Urgency: ROUTINE — Seasonal Planning Cycle

BACKGROUND
----------
The Panama Canal relies on fresh water from Gatun Lake. During the regional dry
season, low rainfall reduces lake levels, forcing the Panama Canal Authority to
implement draft restrictions (reducing maximum vessel cargo weight). Our maritime
logistics planning team requires an assessment of precipitation seasonality over
the Canal region to plan fleet capacity deployment.

DATA REQUIREMENTS
-----------------
- Dataset: NCEP/NCAR Reanalysis Monthly Long-Term Mean Precipitation Rate
  File: ~/PanoplyData/prate.sfc.mon.ltm.nc
  Variable: prate (Surface Precipitation Rate, kg/m²/s)
- Tool: NASA Panoply

REQUIRED ANALYSIS
-----------------
1. Generate an Annual Precipitation Profile:
   - Create a 1D "Line along Time" plot for the approximate coordinates of the
     Panama Canal (Latitude: 9°N, Longitude: 80°W).
     *Note: NCEP longitudes are 0-360°. You may need to use 280°E.*
   - Export this plot to visualize the temporal distribution of rainfall.

2. Generate Spatial Maps for Extremes:
   - Create a 2D geo-mapped plot for the peak dry month (March).
   - Create a 2D geo-mapped plot for the peak wet month (October).
   - For both maps, zoom the view to focus on the Central America region.

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/CanalAssessment/

1. 1D Annual Precipitation Profile:
   Filename: annual_precip_profile.png

2. Central America Precipitation Map (March):
   Filename: panama_precip_march.png

3. Central America Precipitation Map (October):
   Filename: panama_precip_october.png

4. Draft Restriction Risk Report:
   Filename: draft_restriction_report.txt
   Required fields (use EXACTLY these key names, one per line):
     ANALYSIS_REGION: Panama Canal
     CRITICAL_DROUGHT_MONTH: [Name of the month with lowest rainfall, e.g., March]
     PEAK_RECHARGE_MONTH: [Name of the month with highest rainfall, e.g., October]
     DRAFT_RESTRICTION_RISK_MARCH: [HIGH or LOW]
     DRAFT_RESTRICTION_RISK_OCTOBER: [HIGH or LOW]

Submit immediately upon completion.
SPECEOF

chown ga:ga /home/ga/Desktop/canal_assessment_brief.txt
chmod 644 /home/ga/Desktop/canal_assessment_brief.txt
echo "Analysis brief written to ~/Desktop/canal_assessment_brief.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with precipitation data pre-loaded
echo "Launching Panoply with precipitation data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Sources window
focus_panoply
sleep 1

# Pre-select the prate variable (coordinates roughly in the middle of the source window)
DISPLAY=:1 xdotool mousemove 728 530 click 1 2>/dev/null || true
sleep 1

# Take an initial screenshot for verification
take_screenshot /tmp/task_initial.png ga

echo "=== Task Setup Complete ==="