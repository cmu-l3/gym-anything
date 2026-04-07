#!/bin/bash
echo "=== Setting up desert_locust_breeding_habitat task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="desert_locust_breeding_habitat"
PRATE_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
AIR_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/LocustAssessment"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data files exist
if [ ! -f "$PRATE_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $PRATE_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
if [ ! -f "$AIR_FILE" ]; then
    echo "ERROR: Air temperature data file not found: $AIR_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "Precipitation data: $PRATE_FILE ($(stat -c%s "$PRATE_FILE") bytes)"
echo "Air temperature data: $AIR_FILE ($(stat -c%s "$AIR_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/precip_october.png"
rm -f "$OUTPUT_DIR/temperature_october.png"
rm -f "$OUTPUT_DIR/breeding_report.txt"
rm -f /home/ga/Desktop/dlis_october_mandate.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/dlis_october_mandate.txt << 'SPECEOF'
=====================================================
FAO DESERT LOCUST INFORMATION SERVICE (DLIS)
MONTHLY BREEDING CONDITION ASSESSMENT - OCTOBER
=====================================================

TO: DLIS Forecasting Officer
FROM: Senior Locust Forecaster, FAO-DLIS Rome
RE: October Climatological Breeding Assessment

MANDATE:
Prepare the climatological component of the October Desert Locust
Bulletin. Using NCEP/NCAR Reanalysis long-term mean data, assess
breeding suitability across the desert locust recession area.

RECESSION AREA BOUNDS: 15°W to 75°E, 10°N to 40°N

REQUIRED ANALYSIS:
1. Examine October precipitation patterns across the recession area
   - Data: /home/ga/PanoplyData/prate.sfc.mon.ltm.nc (variable: prate)
   - Export plot to: ~/Documents/LocustAssessment/precip_october.png

2. Examine October surface air temperature across the recession area
   - Data: /home/ga/PanoplyData/air.mon.ltm.nc (variable: air)
   - Export plot to: ~/Documents/LocustAssessment/temperature_october.png

3. Write breeding suitability report
   - Save to: ~/Documents/LocustAssessment/breeding_report.txt

BREEDING ECOLOGY REFERENCE:
- Eggs require moist sandy soil (recent rainfall necessary)
- Temperature range for development: 20-38°C (optimal 28-35°C)
- Below 20°C: egg development stalls
- Above 38°C: lethal for eggs in exposed soil

REPORT FORMAT (use exactly these field labels):
  ASSESSMENT_MONTH: [month name]
  RECESSION_AREA_BOUNDS: [geographic bounds used]
  PRIMARY_BREEDING_ZONE: [name of the sub-region with best conditions]
  TEMPERATURE_RANGE_C: [min-max temperature in the breeding zone, °C]
  BREEDING_SUITABILITY: [HIGH/MODERATE/LOW]
  TEMPERATURE_SUITABLE: [YES/NO]
  MOISTURE_ADEQUATE: [YES/NO]
  DATASETS_USED: [list both dataset filenames]

OPERATIONAL CONTEXT:
In October, the Indian Summer Monsoon has retreated. Residual moisture
from monsoon rainfall persists in specific sub-regions. The primary
breeding zone at this time of year is typically where post-monsoon
moisture intersects with warm temperatures in the eastern portion of
the recession area (Hint: Look at the peninsula and the horn). Identify this zone.

DEADLINE: Immediate
=====================================================
SPECEOF

chown ga:ga /home/ga/Desktop/dlis_october_mandate.txt
chmod 644 /home/ga/Desktop/dlis_october_mandate.txt
echo "Mandate written to ~/Desktop/dlis_october_mandate.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with precipitation data pre-loaded
echo "Launching Panoply with prate data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$PRATE_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90

# Let Panoply fully load
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Sources window
focus_panoply
sleep 1

# Take an initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="