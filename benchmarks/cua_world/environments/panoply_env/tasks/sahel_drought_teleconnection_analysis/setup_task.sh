#!/bin/bash
echo "=== Setting up sahel_drought_teleconnection_analysis task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="sahel_drought_teleconnection_analysis"
PRATE_FILE="/home/ga/PanoplyData/prate.sfc.mon.ltm.nc"
SST_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
OUTPUT_DIR="/home/ga/Documents/SahelDrought"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify both data files exist
if [ ! -f "$PRATE_FILE" ]; then
    echo "ERROR: Precipitation data file not found: $PRATE_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
if [ ! -f "$SST_FILE" ]; then
    echo "ERROR: SST data file not found: $SST_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "Precipitation data: $PRATE_FILE ($(stat -c%s "$PRATE_FILE") bytes)"
echo "SST data: $SST_FILE ($(stat -c%s "$SST_FILE") bytes)"

# Create output directory
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/sahel_precip_july.png"
rm -f "$OUTPUT_DIR/pacific_sst_july.png"
rm -f "$OUTPUT_DIR/teleconnection_report.txt"
rm -f /home/ga/Desktop/sahel_drought_mandate.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the analysis mandate to the desktop
cat > /home/ga/Desktop/sahel_drought_mandate.txt << 'SPECEOF'
USDA GLOBAL CLIMATE ASSESSMENT UNIT
INTERNATIONAL FOOD SECURITY MONITORING — ANALYSIS MANDATE
==========================================================
Mandate ID: USDA-GFSA-2024-AF-0312
Analyst Role: Agricultural Climatologist
Program: Global Food Security Assessment

MANDATE OVERVIEW
----------------
The USDA Economic Research Service is publishing the quarterly International
Food Security Assessment for Sub-Saharan Africa. The Sahel region (including
Senegal, Mali, Niger, Burkina Faso, and Chad) is a critical food-insecure zone
where 80% of the population depends on rain-fed agriculture. Rainfall during
the July–September (JAS) season is the primary determinant of annual crop yields.

This assessment requires documentation of the Sahel precipitation climatology
and its teleconnection with equatorial Pacific Sea Surface Temperatures (ENSO).
The Sahel-ENSO teleconnection is a well-documented relationship in which Pacific
SST anomalies modulate the West African Monsoon through changes in the Walker
circulation and moisture transport.

DATA REQUIREMENTS
-----------------
- Dataset 1: NCEP/NCAR Reanalysis Monthly Long-Term Mean Precipitation Rate
  File: ~/PanoplyData/prate.sfc.mon.ltm.nc
  Variable: prate (Surface Precipitation Rate, kg/m²/s)

- Dataset 2: NOAA OI SST v2 Long-Term Mean (1991-2020)
  File: ~/PanoplyData/sst.ltm.1991-2020.nc
  Variable: sst (Sea Surface Temperature, degrees Celsius)

- Target month: July (the core month of the West African Monsoon rainy season)
- Tool: NASA Panoply

REGIONS OF INTEREST
-------------------
1. Sahel region: 15°W to 40°E, 10°N to 18°N
   (Western and Central Sahel — primary rain-fed agricultural zone)

2. Equatorial Pacific (Niño 3.4 region): 120°W to 170°W, 5°S to 5°N
   (Key ENSO monitoring region: SST anomalies here drive global teleconnections)

REQUIRED ANALYSIS
-----------------
Using Panoply, you must:
1. Create and export a July precipitation climatology plot (global or regional)
   that shows the West African Monsoon precipitation band over the Sahel.

2. Create and export a July SST climatology plot (global or regional)
   that shows the equatorial Pacific SST pattern relevant to ENSO.

3. Write a teleconnection assessment report documenting the relationship between
   equatorial Pacific SST and Sahel precipitation.

REQUIRED DELIVERABLES
----------------------
All outputs to: ~/Documents/SahelDrought/

1. Sahel precipitation plot (July):
   Filename: sahel_precip_july.png

2. Equatorial Pacific SST plot (July):
   Filename: pacific_sst_july.png

3. Teleconnection assessment report:
   Filename: teleconnection_report.txt
   Required fields (use EXACTLY these key names, one per line):
     ANALYSIS_REGION_1: Sahel
     ANALYSIS_REGION_2: Equatorial_Pacific
     TARGET_SEASON: JAS
     SAHEL_PRECIP_PATTERN: [1-2 sentences describing the July precipitation pattern over the Sahel]
     ENSO_CONNECTION: [NEGATIVE, POSITIVE, or NEUTRAL —
                       describe the sign of the Sahel-ENSO relationship.
                       NEGATIVE means La Niña (cool Pacific) → enhanced Sahel rainfall,
                       El Niño (warm Pacific) → reduced Sahel rainfall / drought;
                       POSITIVE means the reverse relationship]
     DATA_SOURCES: NCEP/NCAR, NOAA_OI_SST_V2

SCIENTIFIC GUIDANCE
--------------------
The Sahel-ENSO teleconnection operates through the following mechanism:
- During El Niño (warm equatorial Pacific): The Walker circulation weakens,
  reducing moisture convergence over West Africa → DROUGHT in the Sahel.
- During La Niña (cool equatorial Pacific): The Walker circulation strengthens,
  enhancing moisture transport and convergence → ABOVE-NORMAL rainfall in the Sahel.
This is a NEGATIVE teleconnection: warm Pacific SST → reduced Sahel rainfall.
Your task is to document this relationship based on the climatological data.
SPECEOF

chown ga:ga /home/ga/Desktop/sahel_drought_mandate.txt
chmod 644 /home/ga/Desktop/sahel_drought_mandate.txt
echo "Sahel drought mandate written to ~/Desktop/sahel_drought_mandate.txt"

# Kill any existing Panoply instances
pkill -f "Panoply.jar" 2>/dev/null || true
pkill -f "panoply" 2>/dev/null || true
sleep 3

# Launch Panoply with precipitation data as the initial file
# (the agent needs to open SST separately as a second dataset)
echo "Launching Panoply with precipitation data..."
su - ga -c "DISPLAY=:1 /opt/PanoplyJ/panoply.sh '$PRATE_FILE' &"

# Wait for Panoply to start
wait_for_panoply 90

# Let Panoply fully load the file
sleep 10

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 2

# Focus the Sources window
focus_panoply
sleep 1

# Pre-open a precipitation plot to pre-position the analysis
echo "Pre-positioning: creating prate geo-map plot..."
# Close all non-Sources Panoply windows (plot windows covering Sources)
for wid in $(DISPLAY=:1 wmctrl -l 2>/dev/null | awk '{print $1}'); do
    wtitle=$(DISPLAY=:1 xdotool getwindowname "$wid" 2>/dev/null)
    if [[ "$wtitle" == *" in "* ]]; then
        DISPLAY=:1 wmctrl -ic "$wid" 2>/dev/null || true
    fi
done
sleep 2
# Raise and focus the Sources window
SOURCES_ID=$(DISPLAY=:1 xdotool search --onlyvisible --name "Panoply — Sources" 2>/dev/null | head -1)
if [ -n "$SOURCES_ID" ]; then
    DISPLAY=:1 xdotool windowactivate --sync "$SOURCES_ID" 2>/dev/null || true
    DISPLAY=:1 xdotool windowraise "$SOURCES_ID" 2>/dev/null || true
    sleep 1
    # prate is at row 5 in Sources list (header, climatology_bounds, lat, lon, prate, time...)
    # Measured: prate at y=353 in 1280x720 → y=530 in 1920x1080
    DISPLAY=:1 xdotool mousemove 732 530 click --repeat 2 --delay 150 1 2>/dev/null || true
    sleep 3
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
    sleep 8
fi

# Verify plot appeared (match " prate in " with spaces to avoid matching the filename)
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -q " prate in "; then
    echo "Warning: prate plot not found, scanning y range..."
    DISPLAY=:1 xdotool windowactivate --sync "$SOURCES_ID" 2>/dev/null || true
    for vy in 530 510 550 490 570 470; do
        DISPLAY=:1 xdotool windowraise "$SOURCES_ID" 2>/dev/null || true
        sleep 0.3
        DISPLAY=:1 xdotool mousemove 350 $vy click --repeat 2 --delay 150 1 2>/dev/null || true
        sleep 2
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 5
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -q " prate in "; then
            echo "Found prate plot at y=$vy"
            break
        fi
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 1
    done
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== sahel_drought_teleconnection_analysis task setup complete ==="
echo "Precipitation data: $PRATE_FILE"
echo "SST data available: $SST_FILE"
echo "Analysis mandate at: ~/Desktop/sahel_drought_mandate.txt"
echo "Required outputs: sahel_precip_july.png, pacific_sst_july.png, teleconnection_report.txt"
echo "Output directory: $OUTPUT_DIR"
echo "Current windows:"
DISPLAY=:1 wmctrl -l 2>/dev/null || true
