#!/bin/bash
set -e
echo "=== Setting up agn_reverberation_mapping task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Clean up any previous artifacts
rm -rf /home/ga/Images/reverb
rm -f /home/ga/Documents/reverb_mapping_schedule.txt
rm -f /home/ga/Documents/ngc4151_obs_log.txt
rm -f /tmp/task_result.json

# 3. Create output directory structure
mkdir -p /home/ga/Images/reverb/ngc4151/V
mkdir -p /home/ga/Images/reverb/ngc4151/Ha
mkdir -p /home/ga/Documents

# 4. ERROR INJECTION: Seed stale V-band images from 2023
# The agent must not count these or rename them. The verifier uses mtime > task_start_time
touch -t 202301011200 /home/ga/Images/reverb/ngc4151/V/stale_v_001.fits 2>/dev/null || true
touch -t 202301011200 /home/ga/Images/reverb/ngc4151/V/stale_v_002.fits 2>/dev/null || true
touch -t 202301011200 /home/ga/Images/reverb/ngc4151/V/stale_v_003.fits 2>/dev/null || true

chown -R ga:ga /home/ga/Images/reverb
chown -R ga:ga /home/ga/Documents

# 5. Start INDI server and connect devices
ensure_indi_running
sleep 2
connect_all_devices

# 6. Configure filter wheel
# 1=L, 2=V, 3=B, 4=R, 5=Ha, 6=OIII
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=Ha" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_6=OIII" 2>/dev/null || true
sleep 1

# 7. Unpark telescope and slew to WRONG target (M33)
unpark_telescope
sleep 1
# Point at M33 (Triangulum Galaxy)
slew_to_coordinates 1.5639 30.660
wait_for_slew_complete 20
echo "Telescope initially pointed at M33. Agent must slew to NGC 4151."

# 8. Reset CCD to defaults
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 9. Create the observing schedule document
cat > /home/ga/Documents/reverb_mapping_schedule.txt << 'EOF'
AGN REVERBERATION MAPPING - NIGHTLY SCHEDULE
=============================================
Target: NGC 4151 (Seyfert 1 Galaxy)
Coordinates: RA 12h 10m 32s, Dec +39d 24m 21s (J2000)

SCIENTIFIC OBJECTIVE
--------------------
Simultaneous monitoring of the accretion disk continuum (V-band) and the Broad Line Region gas (H-alpha). 
Strict directory isolation is required to prevent pipeline reduction errors.
NOTE: Ignore any stale files from previous runs (e.g., from 2023).

OBSERVATION SEQUENCE
--------------------
1. Slew the telescope to the target coordinates (NGC 4151).

2. CONTINUUM MONITORING (V-Band)
   - Filter: V (Slot 2)
   - Exposure Time: 60 seconds
   - Count: 10 frames (minimum)
   - Upload Directory: /home/ga/Images/reverb/ngc4151/V/

3. BLR MONITORING (H-Alpha)
   - Filter: Ha (Slot 5)
   - Exposure Time: 120 seconds
   - Count: 8 frames (minimum)
   - Upload Directory: /home/ga/Images/reverb/ngc4151/Ha/

4. REFERENCE SKY VIEW
   Capture a 0.5-degree DSS2 reference image using the following exact command:
   bash ~/capture_sky_view.sh ~/Images/reverb/ngc4151/reference_fov.png 0.5 --palette vibrant

5. OBSERVATION LOG
   Create a text file at ~/Documents/ngc4151_obs_log.txt summarizing the night.
   It must explicitly mention:
   - Target name ("NGC 4151")
   - The filters used ("V" and "H-alpha" or "Ha")
   - Total number of frames successfully captured
EOF

chown ga:ga /home/ga/Documents/reverb_mapping_schedule.txt

# 10. Ensure KStars is running, maximized, and focused
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# 11. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="