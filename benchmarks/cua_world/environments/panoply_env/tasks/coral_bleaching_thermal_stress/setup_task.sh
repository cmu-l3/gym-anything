#!/bin/bash
echo "=== Setting up coral_bleaching_thermal_stress task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="coral_bleaching_thermal_stress"
DATA_FILE="/home/ga/PanoplyData/sst.ltm.1991-2020.nc"
OUTPUT_DIR="/home/ga/Documents/ReefStress"
START_TS_FILE="/tmp/${TASK_NAME}_start_ts"

# Verify data file exists
if [ ! -f "$DATA_FILE" ]; then
    echo "ERROR: SST data file not found: $DATA_FILE"
    ls -la /home/ga/PanoplyData/ 2>/dev/null || true
    exit 1
fi
echo "SST data file found: $DATA_FILE ($(stat -c%s "$DATA_FILE") bytes)"

# Create output directory owned by ga
mkdir -p "$OUTPUT_DIR"
chown ga:ga "$OUTPUT_DIR"

# Clean up any pre-existing outputs BEFORE recording start timestamp
rm -f "$OUTPUT_DIR/reef_stress_global_aug.png"
rm -f "$OUTPUT_DIR/reef_stress_hotspot.png"
rm -f "$OUTPUT_DIR/thermal_stress_report.txt"
rm -f /home/ga/Desktop/reef_monitoring_request.txt
echo "Cleaned up pre-existing outputs"

# Record task start timestamp
echo "$(date +%s)" > "$START_TS_FILE"
echo "Task start timestamp: $(cat $START_TS_FILE)"

# Write the monitoring request spec file to the desktop
cat > /home/ga/Desktop/reef_monitoring_request.txt << 'SPECEOF'
NOAA CORAL REEF WATCH — THERMAL STRESS MONITORING REQUEST
==========================================================
Request ID: CRW-2024-AUG-001
Analyst Role: Marine Biologist / Reef Ecosystem Scientist
Priority: HIGH — Potential Mass Bleaching Event

BACKGROUND
----------
Preliminary satellite observations suggest elevated sea surface temperatures across
multiple reef regions during the peak thermal stress season. You are required to
analyze the August climatological SST to identify the most thermally stressed
reef regions and produce a formal thermal stress assessment report.

DATA REQUIREMENTS
-----------------
- Dataset: NOAA OI SST v2 Long-Term Mean (1991-2020)
  File location: ~/PanoplyData/sst.ltm.1991-2020.nc
  Variable: sst (Sea Surface Temperature, degrees Celsius)
  Time step: August (the peak thermal stress month for coral bleaching)
- Tool: NASA Panoply (available in applications menu)

BLEACHING THRESHOLD
-------------------
Coral bleaching thermal stress threshold: 28.2°C
- SST > 28.2°C sustained for multiple weeks → HIGH bleaching risk
- SST 27.0–28.2°C → MEDIUM bleaching risk
- SST < 27.0°C → LOW bleaching risk

REEF REGIONS TO ASSESS
-----------------------
1. Indo-Pacific Warm Pool (100-160°E, 10°S-10°N) — world's largest reef system
2. Coral Triangle (115-155°E, 10°S-15°N) — highest marine biodiversity
3. Caribbean Sea (60-85°W, 10-25°N) — Atlantic reef systems

REQUIRED DELIVERABLES
----------------------
All outputs must be saved to: ~/Documents/ReefStress/

1. Global SST map for August showing all reef regions:
   Filename: reef_stress_global_aug.png
   (Export the full global SST plot using File > Save Image As or equivalent)

2. Zoomed SST map of the MOST thermally stressed reef region:
   Filename: reef_stress_hotspot.png
   (Create a separate zoomed-in plot of the hottest identified region)

3. Thermal stress assessment report:
   Filename: thermal_stress_report.txt
   Required fields (use EXACTLY these key names, one per line):
     MONITORING_DATE: August
     HOTSPOT_REGION: [name of the most thermally stressed region from the list above]
     PEAK_SST: [peak SST value in degrees C, e.g., 29.7]
     BLEACHING_RISK: [HIGH, MEDIUM, or LOW — based on threshold above]
     REGIONS_ASSESSED: [comma-separated list of the 3 regions you examined]

SUBMISSION DEADLINE: Immediate — active bleaching event possible
SPECEOF

chown ga:ga /home/ga/Desktop/reef_monitoring_request.txt
chmod 644 /home/ga/Desktop/reef_monitoring_request.txt
echo "Monitoring request spec file written to ~/Desktop/reef_monitoring_request.txt"

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

# The Sources window shows the variable list.
# For sst.ltm.1991-2020.nc, the 'sst' variable is the main data variable.
# Double-click on 'sst' to open Create Plot dialog, then press Enter for default geo map.
echo "Selecting 'sst' variable to pre-open a geo-mapped plot..."
# In 1920x1080, the variable list is in the Sources window center.
# The sst variable row is approximately at y=530 in the variable list.
DISPLAY=:1 xdotool mousemove 728 530 click --repeat 2 --delay 100 1 2>/dev/null || true
sleep 3

# Press Enter to create the default geo-referenced plot
DISPLAY=:1 xdotool key Return 2>/dev/null || true
sleep 8

# Wait for plot to render
echo "Waiting for SST plot to render..."
sleep 5

# Check if SST plot window appeared
SST_WINDOW=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "sst" | head -1 | awk '{print $1}')
if [ -z "$SST_WINDOW" ]; then
    echo "Warning: SST plot window not found on first try, retrying..."
    DISPLAY=:1 xdotool key ctrl+w 2>/dev/null || true
    sleep 2
    DISPLAY=:1 wmctrl -a "Sources" 2>/dev/null || true
    sleep 1
    for vy in 340 353 366 379 392 405 418 431 444 457 470; do
        DISPLAY=:1 xdotool mousemove 728 $vy click --repeat 2 --delay 100 1 2>/dev/null || true
        sleep 2
        DISPLAY=:1 xdotool key Return 2>/dev/null || true
        sleep 5
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sst"; then
            echo "Found SST plot at y=$vy"
            break
        fi
        DISPLAY=:1 xdotool key Escape 2>/dev/null || true
        sleep 1
    done
fi

# Navigate to August (time step 7, 0-indexed → displayed as month 8)
# The plot window has time navigation arrows at the bottom of the plot
# August is the 8th month; press the right arrow to navigate forward from default (January=0)
# We'll navigate to the August time step (index 7)
echo "Navigating to August time step..."
SST_WINDOW=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "sst" | head -1 | awk '{print $1}')
if [ -n "$SST_WINDOW" ]; then
    DISPLAY=:1 wmctrl -i -a "$SST_WINDOW" 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== coral_bleaching_thermal_stress task setup complete ==="
echo "SST data is loaded in Panoply. A geo-mapped plot of SST is open."
echo "The monitoring request spec is at ~/Desktop/reef_monitoring_request.txt"
echo "Required outputs: reef_stress_global_aug.png, reef_stress_hotspot.png, thermal_stress_report.txt"
echo "All outputs go to: $OUTPUT_DIR"
echo "Current windows:"
DISPLAY=:1 wmctrl -l 2>/dev/null || true
