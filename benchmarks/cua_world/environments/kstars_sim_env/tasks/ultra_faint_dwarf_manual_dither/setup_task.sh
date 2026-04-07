#!/bin/bash
set -e
echo "=== Setting up ultra_faint_dwarf_manual_dither task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded."

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/leo1
rm -f /home/ga/Documents/dither_plan.txt
rm -f /home/ga/Documents/dither_log.txt
rm -f /tmp/task_result.json

# 3. Create output directory structure
mkdir -p /home/ga/Images/leo1/{center,north,south,east,west}
mkdir -p /home/ga/Documents

# 4. ERROR INJECTION: Seed 3 stale FITS files in the center directory
# These pre-date the task start time and must be ignored by the verifier
touch -t 202401010000 /home/ga/Images/leo1/center/stale_frame_01.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/leo1/center/stale_frame_02.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/leo1/center/stale_frame_03.fits 2>/dev/null || true

chown -R ga:ga /home/ga/Images/leo1
chown -R ga:ga /home/ga/Documents

# 5. Start INDI Server and connect devices
ensure_indi_running
sleep 2
connect_all_devices

# 6. Configure filter wheel slots
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# 7. Unpark telescope, slew to Regulus, and PARK it (Agent must unpark to begin)
unpark_telescope
sleep 1
# Point at Regulus (RA 10.13h, Dec 11.96°)
slew_to_coordinates 10.13 11.96
wait_for_slew_complete 25
park_telescope
echo "Telescope slewed to Regulus and parked."

# 8. Reset CCD upload to a neutral local directory
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 9. Create the dither plan document
cat > /home/ga/Documents/dither_plan.txt << 'EOF'
LEO I DWARF SPHEROIDAL - MANUAL DITHER SEQUENCE
================================================
Due to the sequencer failure, execute this 5-point cross dither pattern manually.

Base Target: Leo I Dwarf Galaxy
Filter: Luminance (Slot 1)
Exposure: 45 seconds
Count: 2 LIGHT frames per position

POSITIONS (J2000 Decimal):
1. CENTER : RA 10.1411h, Dec +12.3064°
2. NORTH  : RA 10.1411h, Dec +12.3897° (+5 arcmin Dec)
3. SOUTH  : RA 10.1411h, Dec +12.2231° (-5 arcmin Dec)
4. EAST   : RA 10.1468h, Dec +12.3064° (+5 arcmin RA)
5. WEST   : RA 10.1354h, Dec +12.3064° (-5 arcmin RA)

STORAGE:
Save frames into separate subdirectories based on position:
/home/ga/Images/leo1/center/
/home/ga/Images/leo1/north/
/home/ga/Images/leo1/south/
/home/ga/Images/leo1/east/
/home/ga/Images/leo1/west/

DELIVERABLES:
After all 10 frames are acquired across the 5 folders, write a summary log indicating completion to:
/home/ga/Documents/dither_log.txt

NOTES: 
- Remember to unpark the telescope first.
- The center/ directory may contain bad artifacts from before the crash. Just capture new ones alongside them.
EOF

chown ga:ga /home/ga/Documents/dither_plan.txt

# 10. Ensure KStars is running and maximized
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
echo "Dither plan ready at ~/Documents/dither_plan.txt"