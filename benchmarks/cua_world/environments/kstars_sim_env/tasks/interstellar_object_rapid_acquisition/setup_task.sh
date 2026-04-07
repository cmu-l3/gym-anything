#!/bin/bash
set -e
echo "=== Setting up interstellar_object_rapid_acquisition task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean up previous run artifacts
rm -rf /home/ga/Images/ISO_C2026
rm -f /home/ga/Documents/iso_too_alert.txt
rm -f /home/ga/Documents/iso_report.txt
rm -f /tmp/task_result.json

# 3. Create output directory structure
mkdir -p /home/ga/Images/ISO_C2026
mkdir -p /home/ga/Documents

# ERROR INJECTION: Seed stale FITS files to test anti-gaming
touch -t 202401010000 /home/ga/Images/ISO_C2026/stale_frame_1.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/ISO_C2026/stale_frame_2.fits 2>/dev/null || true

chown -R ga:ga /home/ga/Images/ISO_C2026
chown -R ga:ga /home/ga/Documents

# 4. Ensure INDI server is running
ensure_indi_running
sleep 2
connect_all_devices

# 5. Configure filter wheel
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# 6. Unpark telescope and slew to Sirius (wrong position)
unpark_telescope
sleep 1
slew_to_coordinates 6.75 -16.7
wait_for_slew_complete 20
echo "Telescope at Sirius. Agent must slew to C/2026."

# 7. Configure CCD to defaults (1x1 binning, default upload)
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_BINNING.HOR_BIN=1;VER_BIN=1" 2>/dev/null || true
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 8. Create ToO alert document
cat > /home/ga/Documents/iso_too_alert.txt << 'EOF'
TARGET OF OPPORTUNITY (ToO) ALERT
=================================
Priority: CRITICAL
Classification: Interstellar Object / Fast Mover
Designation: C/2026

An interstellar object has been detected with high proper motion.
Immediate imaging is required before it leaves the observable field.

COORDINATES (J2000):
Right Ascension: 18h 36m 56s
Declination: +38d 47m 01s
Constellation: Lyra

OBSERVING PROTOCOL:
Because this object is moving rapidly, standard long exposures will result in smeared star trails and unusable astrometry. You MUST use short exposures and hardware binning to compensate for the lost signal.

1. Slew the telescope to the coordinates above.
2. Set the filter wheel to Slot 1 (Luminance/Clear).
3. Reconfigure the CCD for 2x2 hardware binning to increase sensitivity.
4. Set the CCD upload directory to: /home/ga/Images/ISO_C2026/
5. Capture exactly 15 LIGHT frames.
6. Set the exposure time for each frame to 5.0 seconds.

THERMAL PROXY MAPPING:
After capturing the FITS sequence, generate a simulated thermal proxy map of the field to estimate the coma's dust temperature.
Run this exact command:
bash ~/capture_sky_view.sh /home/ga/Images/ISO_C2026/thermal_proxy.png 0.25 --palette heat

OBSERVATION REPORT:
Write a brief confirmation report to: ~/Documents/iso_report.txt
Include the following exact details in the text:
- Target designation ("C/2026")
- Number of frames captured ("15")
- Binning mode used ("2x2")
EOF

chown ga:ga /home/ga/Documents/iso_too_alert.txt
echo "Alert written to /home/ga/Documents/iso_too_alert.txt"

# 9. Ensure KStars is running and maximized
ensure_kstars_running
sleep 3

for i in 1 2 3; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# 10. Record initial state
INITIAL_FITS=$(find /home/ga/Images/ISO_C2026 2>/dev/null -name "*.fits" | wc -l)
echo "$INITIAL_FITS" > /tmp/initial_fits_count.txt

# 11. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="