#!/bin/bash
echo "=== Setting up sh_frost_viticulture_planning task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="sh_frost_viticulture_planning"
DATA_FILE="/home/ga/PanoplyData/air.mon.ltm.nc"
OUTPUT_DIR="/home/ga/Documents/FrostRisk"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists (it should be downloaded by install_panoply.sh)
if [ ! -f "$DATA_FILE" ] || [ "$(stat -c%s "$DATA_FILE" 2>/dev/null || echo 0)" -lt 100000 ]; then
    echo "Downloading NCEP surface air temperature data..."
    mkdir -p /home/ga/PanoplyData
    wget -q --timeout=120 \
        "https://downloads.psl.noaa.gov/Datasets/ncep.reanalysis.derived/surface/air.mon.ltm.nc" \
        -O "$DATA_FILE" && echo "Downloaded air.mon.ltm.nc from NOAA PSL" || true
    
    if [ ! -f "$DATA_FILE" ] || [ "$(stat -c%s "$DATA_FILE" 2>/dev/null || echo 0)" -lt 100000 ]; then
        echo "ERROR: Could not download air temperature data"
        exit 1
    fi
fi
chown -R ga:ga /home/ga/PanoplyData
echo "Data file present: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/sh_temperature_july.png"
rm -f "$OUTPUT_DIR/sh_temperature_june.png"
rm -f "$OUTPUT_DIR/frost_risk_report.txt"
rm -f /home/ga/Desktop/frost_advisory_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the advisory request brief to the desktop
cat > /home/ga/Desktop/frost_advisory_request.txt << 'SPECEOF'
=== FROST ADVISORY REQUEST ===
FROM: OIV Climate Services Division
TO: Agricultural Meteorology Team
DATE: Current Assessment Cycle
PRIORITY: Routine Seasonal

SUBJECT: Southern Hemisphere Winter Frost Risk Assessment — Major Wine Regions

BACKGROUND:
The International Organisation of Vine and Wine (OIV) requires an updated frost
risk assessment for the upcoming Southern Hemisphere growing season. Vineyard
managers in three key wine-producing regions need advance guidance on frost
window timing to schedule pruning operations, frost protection activation, and
bud break management.

TARGET REGIONS:
  1. Mendoza, Argentina (~33°S, 69°W) — Malbec/Cabernet production
  2. Western Cape, South Africa (~34°S, 19°E) — Stellenbosch/Paarl
  3. Barossa Valley, South Australia (~35°S, 139°E) — Shiraz/Grenache

ANALYSIS REQUIREMENTS:
  - Use NCEP/NCAR surface air temperature climatology
  - Examine the peak Southern Hemisphere winter months
  - Focus on June and July as the primary frost risk months
  - Produce temperature maps showing the Southern Hemisphere
  - Classify each region's frost risk as HIGH, MODERATE, or LOW
  - Identify which region faces the greatest frost exposure

DATA FILE: /home/ga/PanoplyData/air.mon.ltm.nc
VARIABLE: air (surface air temperature)

DELIVERABLES:
All outputs must be saved to: ~/Documents/FrostRisk/

  1. July temperature map → sh_temperature_july.png
  2. June temperature map → sh_temperature_june.png
  3. Frost risk report → frost_risk_report.txt

REPORT FORMAT (Use exact keys below):
  ANALYSIS_SEASON: [three-letter season code for SH winter, e.g. DJF, MAM, JJA, SON]
  COLDEST_MONTH: [the peak winter month based on your assessment]
  MENDOZA_FROST_RISK: [HIGH/MODERATE/LOW]
  WESTERN_CAPE_FROST_RISK: [HIGH/MODERATE/LOW]
  SOUTH_AUSTRALIA_FROST_RISK: [HIGH/MODERATE/LOW]
  HIGHEST_RISK_REGION: [region name with greatest frost exposure]
  FROST_THRESHOLD_C: [temperature threshold you used, in degrees C]

SCIENTIFIC GUIDANCE:
  - July is typically the coldest month at SH mid-latitudes (30-40°S).
  - Frost risk is HIGH when mean monthly temperature < 8°C.
  - Frost risk is MODERATE when mean monthly temperature is 8-12°C.
  - Frost risk is LOW when mean monthly temperature > 12°C.
  - Continental and elevated regions (like Mendoza) experience colder
    winters than coastal regions at similar latitudes.
=== END REQUEST ===
SPECEOF

chown ga:ga /home/ga/Desktop/frost_advisory_request.txt
chmod 644 /home/ga/Desktop/frost_advisory_request.txt
echo "Advisory request written to ~/Desktop/frost_advisory_request.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with data pre-loaded
echo "Launching Panoply with air temperature data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$DATA_FILE' &"

# Wait for Panoply window
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "panoply"; then
        echo "Panoply window detected"
        break
    fi
    sleep 2
done

# Let Panoply fully load
sleep 8

# Maximize and Focus
DISPLAY=:1 wmctrl -r "Panoply" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Panoply" 2>/dev/null || true

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="