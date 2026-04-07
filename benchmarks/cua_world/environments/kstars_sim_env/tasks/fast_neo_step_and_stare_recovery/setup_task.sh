#!/bin/bash
set -e
echo "=== Setting up fast_neo_step_and_stare_recovery task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/neo_tracking
rm -f /home/ga/Documents/apophis_ephemeris.txt
rm -f /tmp/task_result.json

# 3. Create required directories
mkdir -p /home/ga/Images/neo_tracking
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/neo_tracking
chown -R ga:ga /home/ga/Documents

# 4. Start INDI and Connect Devices
ensure_indi_running
sleep 2
connect_all_devices

# 5. Configure filter wheel slots
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
sleep 1

# 6. Unpark and slew to Polaris (Agent must slew away to the NEO path)
unpark_telescope
sleep 1
slew_to_coordinates 2.53 89.26
wait_for_slew_complete 20
park_telescope
sleep 1
echo "Telescope parked at home position (Polaris)."

# 7. Set default CCD directory to a neutral location
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 8. Create the ephemeris document
cat > /home/ga/Documents/apophis_ephemeris.txt << 'EOF'
=============================================================================
MINOR PLANET CENTER - FAST-MOVING NEO EPHEMERIS
=============================================================================
Object: 99942 Apophis (2029 Close Approach Extract)
Motion: Extremely Fast (Non-Sidereal)

Because the object is moving too fast for standard sidereal tracking, execute a 
"step-and-stare" sequence. Slew to each of the 5 waypoints below in order,
and take a short exposure at each position.

REQUIRED SETTINGS:
- Filter: Clear/Luminance (Filter Wheel Slot 1)
- Exposure time: 10 seconds per waypoint
- Upload Directory: /home/ga/Images/neo_tracking/
- Sequence execution: Slew -> Expose -> Slew -> Expose (do not wait for exact UT times)

WAYPOINTS (J2000):
1. RA: 09h 45m 00s    Dec: +20° 15' 00"
2. RA: 09h 47m 00s    Dec: +19° 50' 00"
3. RA: 09h 49m 00s    Dec: +19° 25' 00"
4. RA: 09h 51m 00s    Dec: +19° 00' 00"
5. RA: 09h 53m 00s    Dec: +18° 35' 00"

POST-PROCESSING REQUIRED:
Compile the 5 captured FITS files into an animated GIF to visually demonstrate 
the shifting starfield. Save the animation as:
/home/ga/Images/neo_tracking/neo_animation.gif

(Animation parameters: 500ms duration per frame, loop infinitely (loop=0), 
normalize contrast mapping the min value to 0 and 99th percentile to 255).
=============================================================================
EOF

chown ga:ga /home/ga/Documents/apophis_ephemeris.txt

# 9. Ensure KStars is running and maximized
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# 10. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="