#!/bin/bash
set -e
echo "=== Setting up high_z_quasar_survey task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any artifacts from previous runs
rm -rf /home/ga/Images/quasars
rm -f /home/ga/Documents/quasar_survey_plan.txt
rm -f /home/ga/Documents/quasar_survey_log.txt
rm -f /tmp/task_result.json

# Create root directories for the survey
mkdir -p /home/ga/Images/quasars/3C273/L
mkdir -p /home/ga/Images/quasars/3C273/R
mkdir -p /home/ga/Images/quasars/TON618
mkdir -p /home/ga/Images/quasars/PG1634
mkdir -p /home/ga/Documents

# ERROR INJECTION: Create decoy files from a "previous shift" that shouldn't be counted
touch -t 202401010000 /home/ga/Images/quasars/3C273/L/old_decoy_001.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/quasars/3C273/L/old_decoy_002.fits 2>/dev/null || true

chown -R ga:ga /home/ga/Images
chown -R ga:ga /home/ga/Documents

# Start INDI and connect devices
ensure_indi_running
sleep 2
connect_all_devices

# Configure filter wheel slots
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=Red" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# Slew to a completely neutral part of the sky (South Galactic Pole area)
unpark_telescope
sleep 1
slew_to_coordinates 0.783 -25.2
wait_for_slew_complete 20

# Set a neutral default CCD state
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# Create the observation plan document
cat > /home/ga/Documents/quasar_survey_plan.txt << 'EOF'
HIGH-REDSHIFT QUASAR BASELINE SURVEY
====================================
Program: AGN Variability Baseline
Priority: HIGH

TARGETS
-------
1. 3C 273 (First discovered quasar)
   RA: 12h 29m 06s
   Dec: +02d 03m 09s (J2000)
   TargetName: 3C273

2. TON 618 (Ultramassive black hole host)
   RA: 12h 28m 25s
   Dec: +35d 58m 01s (J2000)
   TargetName: TON618

3. PG 1634+706
   RA: 16h 34m 29s
   Dec: +70d 31m 32s (J2000)
   TargetName: PG1634

OBSERVATION PROTOCOL (For each target)
--------------------------------------
1. Slew to target coordinates.
2. Capture Luminance (L) frames:
   - Filter: Slot 1 (Luminance)
   - Upload dir: /home/ga/Images/quasars/<TargetName>/L/
   - Exposure: 5 seconds
   - Count: Minimum 3 frames
3. Capture Red (R) frames:
   - Filter: Slot 4 (Red)
   - Upload dir: /home/ga/Images/quasars/<TargetName>/R/
   - Exposure: 5 seconds
   - Count: Minimum 3 frames
4. Fetch DSS2 Reference Image:
   - Command: bash ~/capture_sky_view.sh /home/ga/Images/quasars/<TargetName>/dss2_reference.png 0.5 --palette cool
   - This fetches a 0.5-degree FOV tile matching the current telescope coordinates.
   - The 'cool' palette is critical for highlighting the blue/UV excess of these AGNs.

DELIVERABLES
------------
- Populated FITS directories for all 3 targets (L and R).
- Matching dss2_reference.png in each target's folder.
- A session log file at /home/ga/Documents/quasar_survey_log.txt detailing which targets were successfully observed today.
EOF

chown ga:ga /home/ga/Documents/quasar_survey_plan.txt

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

echo "=== Setup complete ==="