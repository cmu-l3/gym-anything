#!/bin/bash
set -e
echo "=== Setting up ccd_thermal_dark_characterization task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Calibration/thermal
rm -f /home/ga/Documents/thermal_calibration_request.txt
rm -f /home/ga/Documents/thermal_report.txt
rm -f /tmp/task_result.json

# ── 3. Create initial directory structure & Decoy ─────────────────────
mkdir -p /home/ga/Calibration/thermal/0C
mkdir -p /home/ga/Documents

# Create a decoy file with an old timestamp (from 2024)
# This tests if the agent blindly relies on existing files rather than acquiring new ones.
touch -t 202401010000 /home/ga/Calibration/thermal/0C/old_dark.fits 2>/dev/null || true

chown -R ga:ga /home/ga/Calibration
chown -R ga:ga /home/ga/Documents

# ── 4. Start INDI and Configure Devices ────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# Ensure CCD Cooler is OFF initially, so the agent has to turn it on
indi_setprop "CCD Simulator.CCD_COOLER.COOLER_OFF=On" 2>/dev/null || true
# Set ambient temperature simulation (warm)
indi_setprop "CCD Simulator.CCD_TEMPERATURE.CCD_TEMPERATURE_VALUE=20.0" 2>/dev/null || true
sleep 1

# Reset CCD capture parameters
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true
indi_setprop "CCD Simulator.CCD_EXPOSURE.CCD_EXPOSURE_VALUE=1" 2>/dev/null || true

# ── 5. Create the calibration request document ────────────────────────
cat > /home/ga/Documents/thermal_calibration_request.txt << 'EOF'
CCD THERMAL CHARACTERIZATION REQUEST
=====================================
Priority: Standard Calibration Maintenance

OVERVIEW
--------
We need to characterize the dark current of the main CCD at three different
temperature setpoints to build our master dark library.

The CCD simulator realistic cooling delays are enabled. You MUST wait for
the temperature to stabilize at each setpoint before starting the exposures.
If the temperature in the FITS header does not match the setpoint, the
pipeline will reject the frame.

REQUIREMENTS
------------
1. Frame Type: DARK
2. Exposure Time: 60 seconds
3. Frames per setpoint: 3

SETPOINTS & DESTINATIONS
------------------------
Setpoint 1: 0°C
Upload Directory: /home/ga/Calibration/thermal/0C/

Setpoint 2: -10°C
Upload Directory: /home/ga/Calibration/thermal/minus10C/

Setpoint 3: -20°C
Upload Directory: /home/ga/Calibration/thermal/minus20C/

DELIVERABLES
------------
After acquiring all frames, write a brief summary report to:
/home/ga/Documents/thermal_report.txt

The report must confirm which temperatures were successfully characterized
(mention 0, -10, and -20 in the text).

NOTE
----
There may be stale data from previous months in the directories. Do not
count old files; capture new ones. Ensure the CCD Cooler is turned ON.
EOF

chown ga:ga /home/ga/Documents/thermal_calibration_request.txt

# ── 6. Ensure KStars is running ────────────────────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2 3; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
done

maximize_kstars
focus_kstars
sleep 1

# ── 7. Record initial state ────────────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Spec at ~/Documents/thermal_calibration_request.txt"
echo "Cooler is currently OFF. Ambient temp is ~20°C."