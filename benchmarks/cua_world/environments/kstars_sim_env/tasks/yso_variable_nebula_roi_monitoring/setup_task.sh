#!/bin/bash
set -e
echo "=== Setting up yso_variable_nebula_roi_monitoring task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/yso
rm -f /home/ga/Documents/yso_roi_plan.txt
rm -f /tmp/task_result.json

# 3. Create target directories
mkdir -p /home/ga/Images/yso/ngc2261
mkdir -p /home/ga/Images/yso/ngc1555
mkdir -p /home/ga/Images/yso/mcneils
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/yso
chown -R ga:ga /home/ga/Documents

# 4. Start INDI and connect devices
ensure_indi_running
sleep 2
connect_all_devices

# 5. Reset CCD to full frame defaults (4096 x 4096)
indi_setprop "CCD Simulator.CCD_FRAME.WIDTH=4096;HEIGHT=4096;X=0;Y=0" 2>/dev/null || true
indi_setprop "CCD Simulator.CCD_BINNING.HOR_BIN=1;VER_BIN=1" 2>/dev/null || true
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true
set_ccd_upload_dir "/home/ga/Images/captures"
sleep 1

# 6. Unpark and slew to NCP (away from targets)
unpark_telescope
sleep 1
slew_to_coordinates 0.0 89.0
wait_for_slew_complete 20
echo "Telescope parked at NCP. Agent must slew to targets."

# 7. Create the observing plan document
cat > /home/ga/Documents/yso_roi_plan.txt << 'EOF'
YSO VARIABLE NEBULA MONITORING PLAN
===================================
Priority: High (Bandwidth Restricted)

Tonight's remote link is experiencing severe packet loss. To minimize download 
times for these compact nebulae, you MUST use sensor subframing (ROI).

SENSOR INFORMATION
------------------
Our primary CCD sensor is exactly 4096 x 4096 pixels.
You must configure the INDI CCD settings to read out only a 1024 x 1024 
Region of Interest (ROI) that is PERFECTLY CENTERED on the sensor. 
Calculate the required X and Y starting offsets carefully! 
(Hint: (Full_Size - ROI_Size) / 2)

TARGETS & EXPOSURE PLAN
-----------------------
Capture 3 x 60s Luminance exposures for each of the following targets.
Change the upload directory for each target.

1. NGC 2261 (Hubble's Variable Nebula)
   RA: 06h 39m 10s   Dec: +08d 44m 40s
   Dir: /home/ga/Images/yso/ngc2261/

2. NGC 1555 (Hind's Variable Nebula)
   RA: 04h 21m 57s   Dec: +19d 32m 07s
   Dir: /home/ga/Images/yso/ngc1555/

3. McNeil's Nebula
   RA: 05h 46m 14s   Dec: -00d 05m 55s
   Dir: /home/ga/Images/yso/mcneils/

CLEANUP & CONTEXT (CRITICAL)
----------------------------
1. AFTER all narrowband observations are complete, you MUST restore the CCD 
   back to full-frame mode (Width=4096, Height=4096, X=0, Y=0) so you don't 
   break tomorrow's automated full-field survey scripts!
2. Finally, run the context sky capture script on McNeil's Nebula field:
   bash ~/capture_sky_view.sh /home/ga/Images/yso/mcneils/sky_context.png

Note: Do not start taking images until the telescope slew has fully completed.
EOF

chown ga:ga /home/ga/Documents/yso_roi_plan.txt

# 8. Ensure KStars is running
ensure_kstars_running
sleep 3
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done
maximize_kstars
focus_kstars
sleep 1

# 9. Record initial FITS count
INITIAL_FITS=$(find /home/ga/Images/yso 2>/dev/null -name "*.fits" | wc -l)
echo "$INITIAL_FITS" > /tmp/initial_fits_count.txt
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="