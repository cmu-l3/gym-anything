#!/bin/bash
set -e
echo "=== Setting up ccd_photometric_linearity_calibration task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time (anti-gaming) ───────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Images/engineering
rm -f /home/ga/Documents/linearity_test_plan.txt
rm -f /home/ga/Documents/linearity_test_report.txt
rm -f /tmp/task_result.json

# ── 3. Create output directory structure ──────────────────────────────
mkdir -p /home/ga/Images/engineering/linearity/V
mkdir -p /home/ga/Images/engineering/linearity/B
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/engineering
chown -R ga:ga /home/ga/Documents

# ── 4. TRAP/ERROR INJECTION: Seed stale FITS files ────────────────────
# These mimic an aborted run from the past. The agent must either overwrite
# them or the verifier will ignore them based on their old mtime.
dd if=/dev/zero of=/home/ga/Images/engineering/linearity/V/sim_1s.fits bs=1024 count=5 2>/dev/null
dd if=/dev/zero of=/home/ga/Images/engineering/linearity/V/sim_2s.fits bs=1024 count=5 2>/dev/null
touch -t 202401010000 /home/ga/Images/engineering/linearity/V/sim_1s.fits
touch -t 202401010000 /home/ga/Images/engineering/linearity/V/sim_2s.fits
chown -R ga:ga /home/ga/Images/engineering/linearity/V

# ── 5. Ensure INDI server is running with all simulators ──────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 6. Configure filter wheel ─────────────────────────────────────────
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 7. Park telescope to the pole (far from M67) ──────────────────────
park_telescope
sleep 1
# Optionally unpark and slew to 0,0 to ensure it's not near M67
unpark_telescope
sleep 1
slew_to_coordinates 0.0 0.0
wait_for_slew_complete 20
echo "Telescope at Celestial Equator. Agent must find M67."

# ── 8. Configure CCD to neutral state ─────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 9. Create the Engineering Test Plan document ──────────────────────
cat > /home/ga/Documents/linearity_test_plan.txt << 'EOF'
CCD LINEARITY CHARACTERIZATION PLAN
====================================
Purpose: Determine the full-well capacity and photometric linearity
         curve for the primary science CCD.

TARGET FIELD
------------
Target: M67 (Dense, well-calibrated open cluster)
Coordinates:
  RA:  08h 51m 18s
  Dec: +11d 48m 00s

OBSERVATION SEQUENCE
--------------------
To construct an accurate ADU response curve, we must capture exactly one LIGHT
frame at each exposure time in a strict base-2 geometric progression:
  1 second
  2 seconds
  4 seconds
  8 seconds
  16 seconds
  32 seconds

This sequence must be executed for TWO filters:
1. V-Band (Filter Wheel Slot 2)
   Upload Directory: /home/ga/Images/engineering/linearity/V/
   Note: Beware of stale files in this directory from a previous aborted run.
   Take all 6 exposures (1s, 2s, 4s, 8s, 16s, 32s).

2. B-Band (Filter Wheel Slot 3)
   Upload Directory: /home/ga/Images/engineering/linearity/B/
   Take all 6 exposures (1s, 2s, 4s, 8s, 16s, 32s).

REFERENCE IMAGE
---------------
Capture a sky view reference of the M67 field to confirm pointing.
Use the following command:
bash ~/capture_sky_view.sh /home/ga/Images/engineering/m67_reference.png 0.5 --palette cool

REPORT
------
Create a simple execution report at:
/home/ga/Documents/linearity_test_report.txt
The report must confirm that the M67 linearity sequence was successfully 
completed across both V and B filters.
EOF

chown ga:ga /home/ga/Documents/linearity_test_plan.txt
echo "Engineering test plan written to /home/ga/Documents/linearity_test_plan.txt"

# ── 10. Ensure KStars is running and maximized ────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 11. Take initial screenshot ───────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Engineering Plan: ~/Documents/linearity_test_plan.txt"