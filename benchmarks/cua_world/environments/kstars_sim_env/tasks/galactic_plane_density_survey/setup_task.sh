#!/bin/bash
set -e
echo "=== Setting up galactic_plane_density_survey task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/galactic_survey
rm -f /home/ga/Documents/survey_plan.txt
rm -f /home/ga/Documents/galactic_survey_report.txt
rm -f /tmp/task_result.json

# 3. Create root directory
mkdir -p /home/ga/Images/galactic_survey
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/galactic_survey
chown -R ga:ga /home/ga/Documents

# 4. Start INDI
ensure_indi_running
sleep 2
connect_all_devices

# 5. Configure filter wheel and set wrong initial filter
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_SLOT.FILTER_SLOT_VALUE=3" 2>/dev/null || true
sleep 1

# 6. Unpark and slew to NCP (wrong position far from Galactic plane)
unpark_telescope
sleep 1
slew_to_coordinates 0.0 89.0
wait_for_slew_complete 20
echo "Telescope pointed at NCP. Agent must slew to the 6 survey fields."

# 7. Reset CCD
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 8. Create survey plan document
cat > /home/ga/Documents/survey_plan.txt << 'EOF'
GALACTIC PLANE STELLAR DENSITY PILOT SURVEY
============================================
PI: Dr. Elaine Vasquez, Galactic Structure Group
Date: Current Semester
Telescope: Observatory Simulator (200mm f/3.75)
CCD: Simulator CCD

PURPOSE:
Obtain multi-field imaging data along the Galactic plane to demonstrate
stellar density gradient from l=0° (Galactic Center) to l=180° (anti-center)
and key spiral arm crossings. Data will support a full survey proposal.

FILTER: Luminance (Clear) — Filter Slot 1
EXPOSURE: 30 seconds per frame
MINIMUM FRAMES PER FIELD: 2

IMAGE STORAGE:
All images must be saved under /home/ga/Images/galactic_survey/
Each field in its own subdirectory: field_01/ through field_06/

SKY VIEW CAPTURES:
Use ~/capture_sky_view.sh to obtain processed sky survey images.
Capture a sky view for at least 3 of the 6 fields.
Save captures to the same field subdirectory.

SURVEY FIELDS:
==============
Field  Galactic    RA (J2000)         Dec (J2000)        Region
-----  --------    ----------         ----------         ------
 01    l=0°        17h 45m 40s        -29° 00' 28"       Galactic Center (Sgr)
 02    l=27°       18h 47m 00s        -06° 00' 00"       Scutum Star Cloud
 03    l=80°       20h 33m 00s        +40° 08' 00"       Cygnus X Complex
 04    l=120°      01h 00m 00s        +62° 00' 00"       Cassiopeia (Perseus Arm)
 05    l=180°      05h 46m 00s        +28° 56' 00"       Anti-center (Auriga)
 06    l=265°      08h 36m 00s        -45° 10' 00"       Vela/Carina

DECIMAL COORDINATES (for INDI commands):
  Field 01: RA=17.7611  Dec=-29.0078
  Field 02: RA=18.7833  Dec=-6.0000
  Field 03: RA=20.5500  Dec=+40.1333
  Field 04: RA=1.0000   Dec=+62.0000
  Field 05: RA=5.7667   Dec=+28.9333
  Field 06: RA=8.6000   Dec=-45.1667

DELIVERABLE:
Write a survey completion report to:
  /home/ga/Documents/galactic_survey_report.txt

The report must include:
- Header identifying the survey
- A table with one row per field listing:
    * Field number
    * RA and Dec observed
    * Number of CCD frames obtained
    * Number of sky view captures
    * Brief qualitative note (e.g., "dense field", "sparse field")
- Total frame count across all fields
EOF

chown ga:ga /home/ga/Documents/survey_plan.txt

# 9. Ensure KStars is running
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# 10. Record initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="