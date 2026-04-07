#!/bin/bash
set -e
echo "=== Setting up hubble_sequence_rgb_survey task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/galaxy_survey
rm -f /home/ga/Documents/galaxy_survey_plan.txt
rm -f /home/ga/Documents/galaxy_survey_catalog.txt
rm -f /tmp/task_result.json

# 3. Create survey base directory and error injection directory
mkdir -p /home/ga/Images/galaxy_survey/M87/R
mkdir -p /home/ga/Documents

# 4. ERROR INJECTION: Seed stale files with old timestamps (must be ignored by agent/verifier)
touch -t 202401150800 /home/ga/Images/galaxy_survey/M87/R/old_survey_001.fits 2>/dev/null || true
touch -t 202401150800 /home/ga/Images/galaxy_survey/M87/R/old_survey_002.fits 2>/dev/null || true

chown -R ga:ga /home/ga/Images/galaxy_survey
chown -R ga:ga /home/ga/Documents

# 5. Ensure INDI server is running with all simulators
ensure_indi_running
sleep 2
connect_all_devices

# 6. Configure filter wheel for RGB
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# 7. Unpark telescope and slew to Polaris (WRONG position for survey targets)
unpark_telescope
sleep 1
slew_to_coordinates 2.5 89.3
wait_for_slew_complete 20
echo "Telescope at Polaris (RA 2.5h, Dec +89.3°). Agent must slew to targets."

# 8. Reset CCD to defaults
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 9. Create the survey plan document for the agent
cat > /home/ga/Documents/galaxy_survey_plan.txt << 'EOF'
GALAXY MORPHOLOGY RGB IMAGING SURVEY
=====================================
PI: Dr. Elena Vasquez, Dept. of Extragalactic Astronomy
Date: Current Session
Telescope: 200mm f/3.75 Newtonian (via INDI Telescope Simulator)
CCD: INDI CCD Simulator
Purpose: Build RGB imaging atlas spanning the Hubble morphological sequence

FILTER CONFIGURATION
--------------------
Slot 2: V-band (use as Green channel)
Slot 3: B-band (Blue channel)
Slot 4: R-band (Red channel)

All exposures are LIGHT frames.

TARGET LIST
-----------
#  Object     Hubble Type   RA (J2000)        Dec (J2000)       Exp(s)  Frames/filter
1  M87        E0 (cD)       12h 30m 49s       +12d 23m 28s      10      >=2
2  M104       Sa            12h 39m 59s       -11d 37m 23s      10      >=2
3  M51        Sc            13h 29m 53s       +47d 11m 43s      10      >=2
4  NGC4449    IBm (Irr)     12h 28m 11s       +44d 05m 40s      15      >=2

DIRECTORY STRUCTURE
-------------------
Base: /home/ga/Images/galaxy_survey/
Each object gets: <object>/R/, <object>/V/, <object>/B/
Set CCD upload directory before each filter series.

NOTE: There are leftover files in M87/R/ from a previous aborted session.
      Ignore them — they are stale and incomplete.

DELIVERABLES
------------
1. FITS frames in the correct directories (>=2 per filter per object)
2. Sky view capture for each field (use: bash ~/capture_sky_view.sh <output_path>)
3. False-color composite for each object (use: python3 ~/false_color.py <input> <output> --palette enhanced)
   Save as: /home/ga/Images/galaxy_survey/<object>/composite_<object>.png
4. Survey catalog: /home/ga/Documents/galaxy_survey_catalog.txt
   Format per line: <object> | <Hubble_type> | <RA> | <Dec> | <R_frames> | <V_frames> | <B_frames> | <notes>
EOF

chown ga:ga /home/ga/Documents/galaxy_survey_plan.txt
echo "Survey plan written to /home/ga/Documents/galaxy_survey_plan.txt"

# 10. Ensure KStars is running and maximized
ensure_kstars_running
sleep 3

for i in 1 2 3; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# 11. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="