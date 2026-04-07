#!/bin/bash
set -e
echo "=== Setting up wide_field_dark_nebula_survey task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/survey
rm -f /home/ga/Documents/dark_nebula_plan.txt
rm -f /home/ga/Documents/survey_log.txt
rm -f /tmp/task_result.json

# 3. Create target directories
mkdir -p /home/ga/Images/survey/B33
mkdir -p /home/ga/Images/survey/B143
mkdir -p /home/ga/Images/survey/B86
mkdir -p /home/ga/Documents

# 4. Anti-gaming: Pre-seed stale FITS in B33 directory
# (These have old timestamps and must not be counted by the verifier)
touch -t 202401010000 /home/ga/Images/survey/B33/old_B33_001.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/survey/B33/old_B33_002.fits 2>/dev/null || true

chown -R ga:ga /home/ga/Images/survey
chown -R ga:ga /home/ga/Documents

# 5. Start INDI server and connect devices
ensure_indi_running
sleep 2
connect_all_devices

# 6. Configure CCD Simulator for Narrow Field (2500mm FL)
# The agent must change this to 135mm!
indi_setprop "CCD Simulator.SCOPE_INFO.FOCAL_LENGTH=2500" 2>/dev/null || true
indi_setprop "CCD Simulator.SCOPE_INFO.APERTURE=250" 2>/dev/null || true
sleep 1

# 7. Unpark telescope and slew to M31 (wrong target area)
unpark_telescope
sleep 1
slew_to_coordinates 0.712 41.269
wait_for_slew_complete 20
echo "Telescope initialized at M31. Agent must discover and slew to target coordinates."

# 8. Reset CCD default upload directory
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 9. Create the observing plan document
cat > /home/ga/Documents/dark_nebula_plan.txt << 'EOF'
WIDE-FIELD DARK NEBULA SURVEY PLAN
==================================
Project: Barnard Catalog Imaging
Instrument: Observatory CCD

INSTRUMENT RECONFIGURATION REQUIRED
-----------------------------------
The telescope is currently configured for narrow-field high-resolution
imaging (Focal Length: 2500mm). Dark nebulae are large, extended targets
that will not fit in this field of view.

Before starting the survey, you MUST logically reconfigure the CCD Simulator
optics via the INDI control panel to a wide-field telephoto setup:
  - New Focal Length: 135 mm
  - New Aperture: 50 mm

Failure to do this will result in images that are completely useless.

TARGETS
-------
Target 1: Barnard 33 (Horsehead Nebula)
  RA:  05h 40m 59s
  Dec: -02d 27m 30s
  Upload Dir: /home/ga/Images/survey/B33/

Target 2: Barnard 143 (Barnard's E)
  RA:  19h 40m 42s
  Dec: +10d 57m 00s
  Upload Dir: /home/ga/Images/survey/B143/

Target 3: Barnard 86 (Ink Spot Nebula)
  RA:  18h 03m 00s
  Dec: -27d 52m 00s
  Upload Dir: /home/ga/Images/survey/B86/

OBSERVING PROTOCOL
------------------
For EACH of the three targets:
1. Slew to the coordinates.
2. Set the CCD upload directory to the target's folder.
3. Capture at least two 60-second exposures (LIGHT frames).
4. Capture a 15-degree contextual sky view using the provided script:
   Command: bash ~/capture_sky_view.sh /home/ga/Images/survey/<target_name>/sky_view.png 15

SURVEY LOG
----------
After completing all observations, create a text file at:
/home/ga/Documents/survey_log.txt

List the targets you successfully observed and explicitly confirm that the
optics were reconfigured to 135mm focal length.
EOF

chown ga:ga /home/ga/Documents/dark_nebula_plan.txt

# 10. Start and maximize KStars
ensure_kstars_running
sleep 3
for i in 1 2; do DISPLAY=:1 xdotool key Escape 2>/dev/null || true; sleep 1; done
maximize_kstars
focus_kstars
sleep 1

# 11. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Plan located at: ~/Documents/dark_nebula_plan.txt"