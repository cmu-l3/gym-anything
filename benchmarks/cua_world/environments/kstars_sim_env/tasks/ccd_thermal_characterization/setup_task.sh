#!/bin/bash
set -e
echo "=== Setting up ccd_thermal_characterization task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time ─────────────────────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous artifacts ────────────────────────────────────
rm -rf /home/ga/Calibration/thermal_profile
rm -f /home/ga/Documents/thermal_characterization_procedure.txt
rm -f /home/ga/Documents/thermal_report.txt
rm -f /tmp/task_result.json

# ── 3. Create directories ──────────────────────────────────────────────
mkdir -p /home/ga/Calibration/thermal_profile
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Calibration
chown -R ga:ga /home/ga/Documents

# ── 4. Anti-gaming / error injection ───────────────────────────────────
mkdir -p /home/ga/Calibration/thermal_profile/minus10C
touch -t 202401010000 /home/ga/Calibration/thermal_profile/minus10C/old_dark_001.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Calibration/thermal_profile/minus10C/old_dark_002.fits 2>/dev/null || true
chown -R ga:ga /home/ga/Calibration/thermal_profile/minus10C

# ── 5. Start INDI ──────────────────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 6. Set CCD to default (cooler off, temp ambient) ──────────────────
indi_setprop "CCD Simulator.CCD_COOLER.COOLER_ON=Off" 2>/dev/null || true
park_telescope 2>/dev/null || true
indi_setprop "CCD Simulator.UPLOAD_MODE.UPLOAD_LOCAL=On" 2>/dev/null || true

# ── 7. Create procedure document ──────────────────────────────────────
cat > /home/ga/Documents/thermal_characterization_procedure.txt << 'EOF'
CCD THERMAL CHARACTERIZATION PROCEDURE
======================================
Prepared by: Instrumentation Engineering
Target Sensor: Back-illuminated CCD Simulator

OVERVIEW
--------
We need to characterize the dark current generation of the newly installed CCD
at different operating temperatures. The sensor must be physically cooled and
allowed to stabilize before taking exposures.

PROCEDURE
---------
1. Ensure the telescope is parked.
2. Turn ON the CCD cooler.
3. For each temperature setpoint (0°C, -10°C, -20°C):
   a. Command the CCD temperature to the setpoint.
   b. WAIT for the sensor temperature to stabilize (within 0.5°C of target).
      *Do not expose while the temperature is changing!*
   c. Set the exposure type to DARK.
   d. Set exposure time to 60 seconds.
   e. Set the upload directory exactly as specified below.
   f. Capture exactly 5 dark frames.

REQUIRED DIRECTORIES (Case Sensitive)
-------------------------------------
0°C Setpoint:    /home/ga/Calibration/thermal_profile/0C/
-10°C Setpoint:  /home/ga/Calibration/thermal_profile/minus10C/
-20°C Setpoint:  /home/ga/Calibration/thermal_profile/minus20C/

COMPLETION REPORT
-----------------
Once all 15 frames (5 per setpoint) are successfully captured, create a
brief completion report at:
/home/ga/Documents/thermal_report.txt

It just needs to state "Thermal profile complete."

NOTE ON PREVIOUS RUN:
A previous run crashed during the -10°C sequence. There may be some stale
files in the minus10C directory. DO NOT delete them, just make sure you
capture 5 NEW frames during your run.
EOF
chown ga:ga /home/ga/Documents/thermal_characterization_procedure.txt

# ── 8. Start KStars ────────────────────────────────────────────────────
ensure_kstars_running
sleep 3
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done
maximize_kstars
focus_kstars
sleep 1

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="