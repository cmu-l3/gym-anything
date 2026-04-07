#!/bin/bash
set -e
echo "=== Setting up photometric_standard_calibration task ==="

source /workspace/scripts/task_utils.sh

# ── 1. Record task start time (anti-gaming) ───────────────────────────
date +%s > /tmp/task_start_time.txt

# ── 2. Clean up previous run artifacts ────────────────────────────────
rm -rf /home/ga/Images/photcal
rm -f /home/ga/Documents/phot_cal_spec.txt
rm -f /tmp/task_result.json

# ── 3. Create root directory (agent must create filter subdirectories) ──
mkdir -p /home/ga/Images/photcal/sa98
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/photcal
chown -R ga:ga /home/ga/Documents

# ── 4. Ensure INDI is running ──────────────────────────────────────────
ensure_indi_running
sleep 2
connect_all_devices

# ── 5. Configure filter wheel: Slot 1=L, Slot 2=V, Slot 3=B, Slot 4=R, Slot 5=I ─
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# ── 6. Unpark telescope, slew to WRONG position ───────────────────────
unpark_telescope
sleep 1
# Point at M42 (Orion) - wrong direction entirely
slew_to_coordinates 5.5881 -5.3911
wait_for_slew_complete 20
echo "Telescope at M42 (wrong). Agent must find SA 98 field."

# ── 7. Reset CCD to defaults ──────────────────────────────────────────
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# ── 8. Create the calibration specification document ──────────────────
cat > /home/ga/Documents/phot_cal_spec.txt << 'EOF'
PHOTOMETRIC STANDARD STAR CALIBRATION SPECIFICATION
====================================================
Observatory: University Remote Observatory (URO)
Prepared by: Principal Investigator
Date: Current observing run

STANDARD FIELD
--------------
Field: Landolt Standard SA 98
RA: 06h 51m 36s
Dec: -00d 17m 00s (J2000)
Standard stars in field: HD 49798 (V=8.33), Landolt SA 98-978 (V=11.0)

OBSERVING PROCEDURE
-------------------
Step 1: Slew telescope to the SA 98 field coordinates above.

Step 2: Execute the following filter sequence, saving each filter's frames
        to its own subdirectory:

        Filter B (slot 3 in filter wheel):
          - Set CCD upload directory: /home/ga/Images/photcal/sa98/B/
          - Frame type: LIGHT
          - Exposure time: 30 seconds
          - Number of frames: 5

        Filter V (slot 2 in filter wheel):
          - Set CCD upload directory: /home/ga/Images/photcal/sa98/V/
          - Frame type: LIGHT
          - Exposure time: 20 seconds
          - Number of frames: 5

        Filter R (slot 4 in filter wheel):
          - Set CCD upload directory: /home/ga/Images/photcal/sa98/R/
          - Frame type: LIGHT
          - Exposure time: 15 seconds
          - Number of frames: 5

Step 3: Capture the sky view of the field:
        bash ~/capture_sky_view.sh /home/ga/Images/photcal/sa98/sky_view.png

Step 4: Create the calibration catalog file at:
        /home/ga/Images/photcal/sa98/calibration_catalog.txt

        Required format:
        # Photometric Calibration Catalog
        # Field: SA 98
        # Filters observed: B, V, R
        # Frames per filter: 5
        # FILTER  NFRAMES  EXPTIME_S  DIR
        B        5        30         /home/ga/Images/photcal/sa98/B/
        V        5        20         /home/ga/Images/photcal/sa98/V/
        R        5        15         /home/ga/Images/photcal/sa98/R/

NOTES
-----
- Create the filter subdirectories (B/, V/, R/) before capturing
- Change the upload directory before each filter series
- All images must be captured during this session (not pre-existing)
- Catalog is required for downstream photometric reduction pipeline
EOF

chown ga:ga /home/ga/Documents/phot_cal_spec.txt
echo "Calibration spec written to /home/ga/Documents/phot_cal_spec.txt"

# ── 9. Ensure KStars is running ────────────────────────────────────────
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# ── 10. Record initial state ───────────────────────────────────────────
INITIAL_FITS=$(find /home/ga/Images/photcal 2>/dev/null -name "*.fits" | wc -l)
echo "$INITIAL_FITS" > /tmp/initial_fits_count.txt

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Spec at ~/Documents/phot_cal_spec.txt"
echo "Target: SA 98 (RA 06h 51m 36s, Dec -00d 17m)"
echo "Telescope at M42 - agent must discover and slew to SA 98"
