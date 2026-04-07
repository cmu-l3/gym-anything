#!/bin/bash
set -e
echo "=== Setting up edge_on_halo_profiling task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/ngc891
rm -f /home/ga/Documents/ngc891_profiling_plan.txt
rm -f /home/ga/Documents/ngc891_observation_log.txt
rm -f /tmp/task_result.json

# 3. Create output directories
mkdir -p /home/ga/Images/ngc891/v_band_highres
mkdir -p /home/ga/Images/ngc891/l_band_binned
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/ngc891
chown -R ga:ga /home/ga/Documents

# 4. ERROR INJECTION: Stale files from a previous run
# Agent must not count these, and verifier must reject them via mtime
touch -t 202301010000 /home/ga/Images/ngc891/v_band_highres/stale_run_001.fits 2>/dev/null || true
touch -t 202301010000 /home/ga/Images/ngc891/v_band_highres/stale_run_002.fits 2>/dev/null || true
touch -t 202301010000 /home/ga/Images/ngc891/v_band_highres/stale_run_003.fits 2>/dev/null || true
chown ga:ga /home/ga/Images/ngc891/v_band_highres/*.fits 2>/dev/null || true

# 5. Start INDI
ensure_indi_running
sleep 2
connect_all_devices

# 6. Configure filter wheel
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# 7. Unpark and slew to wrong position (M31)
unpark_telescope
sleep 1
slew_to_coordinates 0.712 41.269
wait_for_slew_complete 20
echo "Telescope at M31 (wrong). Agent must find NGC 891."

# 8. Reset CCD to defaults (uncooled, binning 1x1, default dir)
indi_setprop "CCD Simulator.CCD_COOLER.COOLER_OFF=On" 2>/dev/null || true
indi_setprop "CCD Simulator.CCD_BINNING.HOR_BIN=1;VER_BIN=1" 2>/dev/null || true
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 9. Create the profiling plan document
cat > /home/ga/Documents/ngc891_profiling_plan.txt << 'EOF'
DUAL-RESOLUTION PROFILING PLAN: NGC 891
========================================
Prepared by: Extragalactic Structure Group

TARGET
------
Object: NGC 891 (Edge-on unbarred spiral galaxy)
Right Ascension: 02h 22m 33s
Declination:     +42d 20m 57s (J2000)
Constellation: Andromeda

OBSERVATIONAL REQUIREMENTS
--------------------------
To profile both the sharp equatorial dust lane and the faint, extended
vertical stellar halo, we require two distinct imaging sequences with
different binning parameters.

Important: Activate CCD cooling and set temperature to -15°C to minimize
thermal noise for the faint halo observations. Wait for it to cool before
starting the halo sequence if possible.

SEQUENCE 1: HIGH-RESOLUTION DUST LANE PROFILING
- Filter: V-band (slot 2)
- Binning: 1x1 (unbinned) for maximum spatial resolution
- Upload directory: /home/ga/Images/ngc891/v_band_highres/
- Exposure time: 15 seconds per frame
- Frames: 5 LIGHT frames
- Note: There are some stale files in this directory from a previous aborted
  run in 2023. Ignore them and capture 5 NEW frames.

SEQUENCE 2: DEEP HALO PROFILING
- Filter: L-band / Luminance (slot 1)
- Binning: 2x2 (binned) to increase SNR for faint surface brightness
- Upload directory: /home/ga/Images/ngc891/l_band_binned/
- Exposure time: 30 seconds per frame
- Frames: 5 LIGHT frames

SKY SURVEY CAPTURE
------------------
Capture a sky view using the standard script:
bash ~/capture_sky_view.sh /home/ga/Images/ngc891/sky_view_ngc891.png

OBSERVATION LOG
---------------
Create a brief text report at /home/ga/Documents/ngc891_observation_log.txt
summarizing that the unbinned V-band and binned L-band sequences were
executed.
EOF

chown ga:ga /home/ga/Documents/ngc891_profiling_plan.txt

# 10. Ensure KStars is running
ensure_kstars_running
sleep 3

for i in 1 2 3; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# 11. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="