#!/bin/bash
set -e
echo "=== Setting up equatorial_mount_pec_calibration task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming validation)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean up any previous run artifacts
rm -rf /home/ga/Images/pec_run
rm -f /home/ga/Documents/pec_work_order.txt
rm -f /home/ga/Documents/pec_summary.txt
rm -f /tmp/task_result.json

mkdir -p /home/ga/Images/pec_run
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images
chown -R ga:ga /home/ga/Documents

# 3. Ensure INDI server is running
ensure_indi_running
sleep 2
connect_all_devices

# 4. Pre-configure INDI Devices (Filter, Focuser, Telescope)
# Setup standard filter names
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# Reset to neutral state: Filter L, Nominal Focus 30000, Parked
indi_setprop "Filter Wheel Simulator.FILTER_SLOT.FILTER_SLOT_VALUE=1" 2>/dev/null || true
indi_setprop "Focuser Simulator.ABS_FOCUS_POSITION.FOCUS_ABSOLUTE_POSITION=30000" 2>/dev/null || true
park_telescope

# 5. Reset CCD Simulator upload path
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 6. Create the Engineering Work Order for the agent to follow
cat > /home/ga/Documents/pec_work_order.txt << 'EOF'
MAINTENANCE WORK ORDER: Periodic Error Correction (PEC) Calibration
===================================================================
Priority: HIGH (Required before science observing season begins)

OBSERVATORY ENGINEERING TASK
----------------------------
The equatorial mount requires a new PEC curve to map and correct worm gear
periodic errors. We need to capture a high-cadence tracking sequence of an
equatorial star over at least one full worm gear cycle.

TARGET
------
Star: Mintaka (Delta Orionis)
RA: 05h 32m 00s
Dec: -00d 17m 57s (J2000)
Reason: Near the celestial equator for maximum tracking drift visibility.

OPTICAL CONFIGURATION
---------------------
Filter: V-band (slot 2)
Reason: Minimizes atmospheric dispersion effects on the star centroid.

Focuser: +1500 step offset from nominal
Nominal focus position is 30000. Set the absolute focus to exactly 31500.
Reason: Defocusing spreads the star's Point Spread Function (PSF) across
more pixels, preventing saturation and allowing for highly accurate sub-pixel
centroiding by the PEC analysis software.

IMAGING SEQUENCE
----------------
Upload Directory: /home/ga/Images/pec_run/
Exposure time: 3 seconds per frame
Count: Capture at least 40 consecutive frames to cover the full worm cycle.

DELIVERABLE
-----------
When the sequence completes, create a simple text report at:
/home/ga/Documents/pec_summary.txt

The report MUST document:
- The target observed
- The absolute focuser position used
- The number of frames successfully captured

Note: Please ensure the mount is unparked and tracking the target before
beginning the exposure sequence.
EOF

chown ga:ga /home/ga/Documents/pec_work_order.txt

# 7. Ensure KStars is running and clear dialogs
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Engineering Work Order placed at: ~/Documents/pec_work_order.txt"