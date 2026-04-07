#!/bin/bash
set -e
echo "=== Setting up supernova_candidate_triage task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Clean up previous artifacts
rm -rf /home/ga/Observations
rm -f /home/ga/Documents/transient_alerts.txt
rm -f /tmp/task_result.json

# Create root directories
mkdir -p /home/ga/Observations
mkdir -p /home/ga/Documents

# Pre-create the target directories to save the agent from doing `mkdir -p` repeatedly
for target in AT2026a AT2026b AT2026c AT2026d; do
    mkdir -p "/home/ga/Observations/$target/fresh"
    mkdir -p "/home/ga/Observations/$target/archive"
done
chown -R ga:ga /home/ga/Observations
chown -R ga:ga /home/ga/Documents

# Ensure INDI server is running with simulators
ensure_indi_running
sleep 2
connect_all_devices

indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
sleep 1

# Unpark and slew to NCP to ensure a neutral starting position
unpark_telescope
sleep 1
slew_to_coordinates 0.0 89.9
wait_for_slew_complete 20
echo "Telescope initialized at North Celestial Pole."

set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# Generate realistic Transient Alert document
cat > /home/ga/Documents/transient_alerts.txt << 'EOF'
TARGET OF OPPORTUNITY ALERT: SUPERNOVA CANDIDATES
=================================================
Facility: Automated Survey for Transients
Date: Current

SAFETY WARNING:
The observatory mount has a physical hard stop at Declination -30 degrees.
DO NOT slew to any target with a Declination below -30d 00m 00s. 
Attempting to do so will cause a mount collision. Exclude these targets.

TARGET LIST:
------------
1. AT2026a
   Host: NGC 3184
   RA: 10h 18m 17s
   Dec: +41d 25m 28s

2. AT2026b
   Host: NGC 1316 (Fornax A)
   RA: 03h 22m 41s
   Dec: -37d 12m 30s

3. AT2026c
   Host: M101
   RA: 14h 03m 12s
   Dec: +54d 20m 56s

4. AT2026d
   Host: M51
   RA: 13h 29m 52s
   Dec: +47d 11m 42s

FOLLOW-UP INSTRUCTIONS:
-----------------------
For each valid target, you must:
1. Slew to the coordinates.
2. Ensure Filter Wheel is on Slot 1 (Luminance).
3. Set the CCD upload directory to ~/Observations/<Target_ID>/fresh/
4. Take a 60-second LIGHT frame.
5. Capture a DSS2 archival field of view (0.5 degrees, 'cool' palette) to:
   ~/Observations/<Target_ID>/archive/dss2.png

Once complete, write a triage report to ~/Observations/triage_report.txt
listing the final status (Imaged vs Skipped) of all four targets.
EOF

chown ga:ga /home/ga/Documents/transient_alerts.txt

# Ensure KStars is running
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# Take initial proof screenshot
take_screenshot /tmp/task_initial.png
echo "=== Task setup complete ==="