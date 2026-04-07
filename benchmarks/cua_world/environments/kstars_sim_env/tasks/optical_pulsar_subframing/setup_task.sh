#!/bin/bash
set -e
echo "=== Setting up optical_pulsar_subframing task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up previous artifacts
rm -rf /home/ga/Images/pulsar_data
rm -f /home/ga/Documents/pulsar_observation_plan.txt
rm -f /tmp/task_result.json
rm -f /tmp/task_start_time.txt

# 2. Create target directories
mkdir -p /home/ga/Images/pulsar_data/crab
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/pulsar_data
chown -R ga:ga /home/ga/Documents

# 3. ANTI-GAMING: Seed stale, full-frame files
# These simulate a previous user's session and must not be counted by the verifier.
echo "Seeding stale FITS files..."
for i in {1..5}; do
    # Create a dummy FITS-like file (just needs to be large enough to pass size checks if checked)
    dd if=/dev/urandom of=/home/ga/Images/pulsar_data/crab/stale_frame_$i.fits bs=1024 count=100 2>/dev/null
    # Set modified time to January 1, 2024
    touch -t 202401010000 /home/ga/Images/pulsar_data/crab/stale_frame_$i.fits
done
chown -R ga:ga /home/ga/Images/pulsar_data/crab

# 4. Record task start time AFTER seeding stale files
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 5. Start INDI Server and Connect Devices
ensure_indi_running
sleep 2
connect_all_devices

# 6. Configure filter wheel
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=Red" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=Green" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=Blue" 2>/dev/null || true
sleep 1

# 7. Slew telescope to wrong position (Betelgeuse)
unpark_telescope
sleep 1
slew_to_coordinates 5.919 7.407
wait_for_slew_complete 20
echo "Telescope initially pointed at Betelgeuse. Agent must slew to Crab Pulsar."

# 8. Reset CCD to defaults (Full frame, 1x1 binning, generic upload dir)
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_BINNING.HOR_BIN=1;VER_BIN=1" 2>/dev/null || true
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 9. Create observation plan
cat > /home/ga/Documents/pulsar_observation_plan.txt << 'EOF'
HIGH-SPEED TIME DOMAIN OBSERVATION REQUEST
==========================================
Target: Crab Pulsar (PSR B0531+21)
Coordinates: RA 05h 34m 32s, Dec +22d 00m 52s

INSTRUMENT CONFIGURATION
------------------------
Filter: Luminance / Clear (Slot 1)
Binning: 2x2 (to maximize SNR on sub-second timescales)

Subframe (Region of Interest): 
We must minimize readout overhead to achieve high frame rates.
  - Set Frame Width to 256
  - Set Frame Height to 256
  - Set X offset to 512
  - Set Y offset to 512

SEQUENCE REQUIREMENTS
---------------------
Exposure: 0.5 seconds per frame
Count: 30 consecutive frames
Upload Path: /home/ga/Images/pulsar_data/crab/

CONTEXT REQUIREMENT
-------------------
Generate a DSS2 sky capture of the field for the observation log.
Output: /home/ga/Images/pulsar_data/crab_context.png
FOV: 0.25 degrees
Palette: vibrant

(Use the standard script: bash ~/capture_sky_view.sh <output> <fov> --palette <name>)
EOF
chown ga:ga /home/ga/Documents/pulsar_observation_plan.txt

# 10. Ensure KStars is running
ensure_kstars_running
sleep 3
for i in 1 2 3; do DISPLAY=:1 xdotool key Escape 2>/dev/null || true; sleep 0.5; done
maximize_kstars
focus_kstars
sleep 1

# 11. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="