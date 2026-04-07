#!/bin/bash
echo "=== Setting up commercial_crew_splashdown_climatology task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="commercial_crew_splashdown_climatology"
PRATE_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
SST_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
OUTPUT_DIR="/home/ga/Documents/RecoveryOps"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify both data files exist
if [ ! -f "$PRATE_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $PRATE_FILE"
    exit 1
fi
if [ ! -f "$SST_FILE" ]; then
    echo "ERROR: SST data file not found: $SST_FILE"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/sst_september.png"
rm -f "$OUTPUT_DIR/precip_september.png"
rm -f "$OUTPUT_DIR/splashdown_recommendation.txt"
rm -f /home/ga/Desktop/splashdown_assessment_mandate.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/splashdown_assessment_mandate.txt << 'SPECEOF'
COMMERCIAL CREW RECOVERY OPERATIONS
SPLASHDOWN WEATHER ASSESSMENT MANDATE
==========================================================
Mandate ID: REC-OPS-2024-SEP-01
Analyst Role: Aerospace Meteorologist

MANDATE OVERVIEW
----------------
A Commercial Crew spacecraft is scheduled for a September return. We must designate a primary splashdown site. Recovery operations are extremely sensitive to sea state, precipitation, and especially tropical cyclones. Tropical cyclones require Sea Surface Temperatures (SST) > 26.5°C to form and sustain themselves.

You are required to evaluate the climatological SST and Precipitation Rate for September to recommend the safest site.

CANDIDATE SITES
---------------
- Site Alpha (Gulf of Mexico): Off the coast of Pensacola, FL (~29°N, 87°W)
- Site Bravo (Pacific Ocean): Off the coast of Baja California (~30°N, 118°W)

DATA REQUIREMENTS
-----------------
- Dataset 1 (SST): ~/PanoplyData/sst.ltm.1991-2020.nc
  Variable: sst (Sea Surface Temperature, Celsius)
- Dataset 2 (Precipitation): ~/PanoplyData/prate.sfc.mon.ltm.nc
  Variable: prate (Precipitation Rate, kg/m²/s)
- Target month: September (time index 8 in Panoply)

REQUIRED ANALYSIS & DELIVERABLES
--------------------------------
Using NASA Panoply, open both datasets, navigate to September, and produce the following exports in ~/Documents/RecoveryOps/ :

1. SST Map:
   Filename: sst_september.png
   (Export a map showing North America and both candidate sites)

2. Precipitation Map:
   Filename: precip_september.png
   (Export a map showing North America and both candidate sites)

3. Recommendation Report:
   Filename: splashdown_recommendation.txt
   Required fields (use EXACTLY these key names, one per line):
     ASSESSMENT_MONTH: September
     SITE_ALPHA_GOM_SST: [Estimated SST in °C for the Gulf site, e.g. 29.5]
     SITE_BRAVO_BAJA_SST: [Estimated SST in °C for the Pacific site, e.g. 22.1]
     CYCLONE_RISK_DRIVER: SST > 26.5C
     RECOMMENDED_SITE: [Alpha or Bravo — choose the colder, drier, safer site]
     PRECIPITATION_COMPARISON: [Brief description of which site is wetter/drier]
SPECEOF

chown ga:ga /home/ga/Desktop/splashdown_assessment_mandate.txt
chmod 644 /home/ga/Desktop/splashdown_assessment_mandate.txt

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with NO datasets loaded
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh &"

# Wait for Panoply to start
wait_for_panoply 90
sleep 5

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

focus_panoply
maximize_panoply

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="