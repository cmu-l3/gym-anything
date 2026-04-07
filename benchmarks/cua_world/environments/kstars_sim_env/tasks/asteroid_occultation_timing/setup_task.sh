#!/bin/bash
set -e
echo "=== Setting up asteroid_occultation_timing task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time (anti-gaming) ───────────────────────────
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# ── 2. Clean up previous run artifacts ────────────────────────────────
rm -rf /home/ga/Images/occultations
rm -f /home/ga/Documents/iota_prediction.txt
rm -f /home/ga/Documents/iota_occultation_report.txt
rm -f /tmp/task_result.json

# ── 3. Create output directory structure ──────────────────────────────
mkdir -p /home/ga/Images/occultations/52europa
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/occultations
chown -R ga:ga /home/ga/Documents

# ── 4. Ensure INDI server is running with all simulators ──────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Configure filter wheel ─────────────────────────────────────────
# Slot 1=Clear/Luminance, Slot 2=V, Slot 3=B, Slot 4=R, Slot 5=I
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Clear" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 6. Unpark telescope and slew to WRONG position ────────────────────
unpark_telescope
sleep 1
# Point at Polaris - completely wrong target area (RA ~2.5h, Dec ~89.2h)
slew_to_coordinates 2.53 89.26
wait_for_slew_complete 20
echo "Telescope at Polaris (wrong position). Agent must slew to TYC 6815."

# ── 7. Configure CCD defaults ─────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 8. Create the prediction document for the agent to discover ───────
cat > /home/ga/Documents/iota_prediction.txt << 'EOF'
IOTA OCCULTATION PREDICTION ALERT
==================================
Event: (52) Europa occults TYC 6815-00874-1
Date: Tonight
Priority: High (Multiple observer verification requested)

TARGET INFORMATION
------------------
Star: TYC 6815-00874-1
Right Ascension: 17h 12m 42.0s
Declination: -24d 51m 30s (J2000)
Constellation: Ophiuchus
Star Magnitude: 9.1 V

ASTEROID INFORMATION
--------------------
Asteroid: (52) Europa
Diameter: ~303 km
Max duration: 14.2s
Shadow velocity: 18.6 km/s

OBSERVING INSTRUCTIONS
----------------------
Telescope must be tracking the target star precisely.
Filter: Clear / Luminance (slot 1) to maximize light throughput.
Exposure time: 2 seconds per frame (rapid cadence required).
Minimum frames: 40 frames continuous sequence.
CCD upload directory: /home/ga/Images/occultations/52europa/

FIELD VERIFICATION
------------------
Please capture a sky view of your target field before starting the sequence:
bash ~/capture_sky_view.sh /home/ga/Images/occultations/52europa/sky_view.png 0.5

REPORT SUBMISSION
-----------------
Submit your observation report to: /home/ga/Documents/iota_occultation_report.txt

Required format fields:
OBSERVER: [Your Name]
EVENT: (52) Europa occults TYC 6815-00874-1
STAR_RA: [RA]
STAR_DEC: [Dec]
FILTER: Clear/Luminance
EXPOSURE: 2s
NUM_FRAMES: [Total frames captured]
UPLOAD_DIR: /home/ga/Images/occultations/52europa/
EOF

chown ga:ga /home/ga/Documents/iota_prediction.txt
echo "Prediction document written to /home/ga/Documents/iota_prediction.txt"

# ── 9. Ensure KStars is running and maximized ─────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 10. Record initial FITS count ─────────────────────────────────────
INITIAL_FITS=$(find /home/ga/Images/occultations 2>/dev/null -name "*.fits" | wc -l)
echo "$INITIAL_FITS" > /tmp/initial_fits_count.txt

# ── 11. Take initial screenshot ───────────────────────────────────────
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="