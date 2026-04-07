#!/bin/bash
echo "=== Setting up malaria_transmission_suitability_mapping task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="malaria_suitability"
DATA_DIR="/home/ga/PanoplyData"
TEMP_FILE="$DATA_DIR/air.mon.ltm.nc"
PRECIP_FILE="$DATA_DIR/prate.sfc.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/MalariaSuitability"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify required data files exist
if [ ! -f "$TEMP_FILE" ]; then
    echo "ERROR: Temperature data file not found: $TEMP_FILE"
    exit 1
fi
if [ ! -f "$PRECIP_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $PRECIP_FILE"
    exit 1
fi

echo "Temperature data: $TEMP_FILE ($(stat -c%s "$TEMP_FILE") bytes)"
echo "Precipitation data: $PRECIP_FILE ($(stat -c%s "$PRECIP_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/temperature_july.png"
rm -f "$OUTPUT_DIR/precipitation_july.png"
rm -f "$OUTPUT_DIR/transmission_suitability_report.txt"
rm -f /home/ga/Desktop/who_malaria_climate_briefing.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis briefing to the desktop
cat > /home/ga/Desktop/who_malaria_climate_briefing.txt << 'SPECEOF'
============================================================
WHO GLOBAL MALARIA PROGRAMME — CLIMATE SUITABILITY ANALYSIS
============================================================

TO:       Climate-Health Analysis Unit
FROM:     Dr. A. Moreira, Programme Coordinator
DATE:     Current
SUBJECT:  July Climatological Suitability Mapping for Malaria Transmission

BACKGROUND:
The Global Technical Strategy for Malaria 2016-2030 requires updated
climate suitability baselines to guide intervention targeting. Your unit
has been tasked with producing a first-order transmission suitability
assessment using NCEP/NCAR reanalysis climatology.

ANALYSIS REQUIREMENTS:
1. Examine JULY climatological surface air temperature from:
   ~/PanoplyData/air.mon.ltm.nc (variable: air)
   
2. Examine JULY climatological precipitation rate from:
   ~/PanoplyData/prate.sfc.mon.ltm.nc (variable: prate)

3. Identify regions where BOTH conditions are met:
   - Temperature within 20-30°C (optimal for Plasmodium falciparum)
   - Sufficient precipitation for Anopheles mosquito breeding habitat

4. Export temperature and precipitation maps to:
   ~/Documents/MalariaSuitability/temperature_july.png
   ~/Documents/MalariaSuitability/precipitation_july.png

5. Write a structured report to:
   ~/Documents/MalariaSuitability/transmission_suitability_report.txt

REPORT FORMAT (use these exact field labels, one per line):
   ANALYSIS_MONTH: [month analyzed]
   TEMP_SUITABILITY_RANGE_C: [temperature range in degrees C]
   PRIMARY_RISK_ZONE: [broad region with highest overlap of both conditions]
   SECONDARY_RISK_ZONE: [broad region with second-highest overlap]
   TRANSMISSION_SUITABILITY: [HIGH/MODERATE/LOW for primary zone]
   DATASETS_USED: [list both datasets]

SCIENTIFIC GUIDANCE:
- Plasmodium falciparum requires 18-33°C for development; optimal is 20-30°C
- Anopheles mosquitoes need standing water from precipitation for breeding
- In July, the ITCZ reaches its northernmost position, bringing rainfall
  to the Sahel and West/Central Africa
- The Indian and Southeast Asian monsoons are active in July
- Focus on where warm temperatures AND precipitation OVERLAP spatially
- Sub-Saharan Africa and Southern/Southeastern Asia are the major historical regions

NOTE: Precipitation rate is in kg/m^2/s. Focus on SPATIAL PATTERNS
(where is it raining vs. dry?) rather than converting units.
============================================================
SPECEOF

chown ga:ga /home/ga/Desktop/who_malaria_climate_briefing.txt
chmod 644 /home/ga/Desktop/who_malaria_climate_briefing.txt
echo "Analysis briefing written to ~/Desktop/who_malaria_climate_briefing.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with no data loaded (agent must open them)
echo "Launching Panoply..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh &"

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

# Maximize the Panoply window
maximize_panoply 2>/dev/null || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Setup complete ==="