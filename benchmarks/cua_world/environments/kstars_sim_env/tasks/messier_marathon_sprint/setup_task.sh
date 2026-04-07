#!/bin/bash
set -e
echo "=== Setting up messier_marathon_sprint task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/marathon
rm -f /home/ga/Documents/marathon_targets.txt
rm -f /home/ga/Documents/marathon_log.txt
rm -f /tmp/task_result.json

# 3. Create document directory
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# 4. Error Injection: Pre-seed stale FITS files for M13 before the task starts
mkdir -p /home/ga/Images/marathon/M13
touch -t 202401150300.00 /home/ga/Images/marathon/M13/old_m13_001.fits
touch -t 202401150300.00 /home/ga/Images/marathon/M13/old_m13_002.fits
chown -R ga:ga /home/ga/Images/marathon

# 5. Ensure INDI server is running and devices are connected
ensure_indi_running
sleep 2
connect_all_devices

# 6. Configure filter wheel slots
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=Ha" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_6=OIII" 2>/dev/null || true
sleep 1

# 7. Slew telescope to Polaris (away from all targets)
unpark_telescope
sleep 1
slew_to_coordinates 2.5301 89.2642
wait_for_slew_complete 20
echo "Telescope at Polaris. Agent must slew to targets."

# 8. Reset CCD upload to a neutral default
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 9. Create marathon target sheet
cat > /home/ga/Documents/marathon_targets.txt << 'EOF'
========================================================
    MESSIER MARATHON SPRINT — Target Sheet
    Spring 2025 Session
========================================================

Complete the following 6 Messier objects. For each target:
  - Slew the telescope to the listed coordinates
  - Set the specified filter
  - Configure CCD upload to: /home/ga/Images/marathon/<TargetName>/
  - Capture the required number of LIGHT frames at the listed exposure time

FILTER WHEEL CONFIGURATION:
  Slot 1: Luminance (clear)
  Slot 2: V (Johnson Visual, 551nm)
  Slot 3: B (Johnson Blue, 445nm)
  Slot 4: R (Cousins Red, 658nm)
  Slot 5: Ha (Hydrogen-alpha, 656nm narrowband)
  Slot 6: OIII (Oxygen-III, 500nm narrowband)

TARGET LIST (observe in order):
--------------------------------------------------------------
#1  M1  — Crab Nebula (supernova remnant)
    RA:  05h 34m 31.9s  (decimal: 5.5755h)
    Dec: +22° 00' 52"   (decimal: +22.0144°)
    Filter: Ha (slot 5)
    Exposure: 60 seconds
    Frames needed: 2
    Upload dir: /home/ga/Images/marathon/M1/

#2  M13 — Great Globular Cluster in Hercules
    RA:  16h 41m 41.6s  (decimal: 16.6949h)
    Dec: +36° 27' 41"   (decimal: +36.4614°)
    Filter: V (slot 2)
    Exposure: 30 seconds
    Frames needed: 3
    Upload dir: /home/ga/Images/marathon/M13/
    NOTE: Previous session left stale files here. Ignore them; capture 3 fresh frames.

#3  M27 — Dumbbell Nebula (planetary nebula)
    RA:  19h 59m 36.3s  (decimal: 19.9934h)
    Dec: +22° 43' 16"   (decimal: +22.7211°)
    Filter: Ha (slot 5)
    Exposure: 45 seconds
    Frames needed: 2
    Upload dir: /home/ga/Images/marathon/M27/

#4  M51 — Whirlpool Galaxy (interacting spiral)
    RA:  13h 29m 52.7s  (decimal: 13.4980h)
    Dec: +47° 11' 43"   (decimal: +47.1953°)
    Filter: R (slot 4)
    Exposure: 60 seconds
    Frames needed: 2
    Upload dir: /home/ga/Images/marathon/M51/

#5  M57 — Ring Nebula (planetary nebula)
    RA:  18h 53m 35.1s  (decimal: 18.8931h)
    Dec: +33° 01' 45"   (decimal: +33.0292°)
    Filter: Ha (slot 5)
    Exposure: 45 seconds
    Frames needed: 2
    Upload dir: /home/ga/Images/marathon/M57/

#6  M101 — Pinwheel Galaxy (grand-design spiral)
    RA:  14h 03m 12.6s  (decimal: 14.0535h)
    Dec: +54° 20' 57"   (decimal: +54.3492°)
    Filter: V (slot 2)
    Exposure: 90 seconds
    Frames needed: 2
    Upload dir: /home/ga/Images/marathon/M101/

--------------------------------------------------------------
AFTER COMPLETING ALL TARGETS:
  1. Capture a sky view of the final target (M101):
     bash ~/capture_sky_view.sh ~/Images/marathon/sky_view_m101.png

  2. Write an observation log to:
     /home/ga/Documents/marathon_log.txt
     Include: target name, coordinates, filter, frames captured for each.

Good luck and clear skies!
========================================================
EOF
chown ga:ga /home/ga/Documents/marathon_targets.txt

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