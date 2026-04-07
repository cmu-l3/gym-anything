#!/bin/bash
set -e
echo "=== Setting up atmospheric_extinction_acquisition task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/extinction
rm -f /home/ga/Documents/extinction_targets.txt
rm -f /home/ga/Documents/extinction_report.txt
rm -f /tmp/task_result.json

# 3. Create required root directories
mkdir -p /home/ga/Images/extinction
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/extinction
chown -R ga:ga /home/ga/Documents

# 4. Ensure INDI is running and connect devices
ensure_indi_running
sleep 2
connect_all_devices

# 5. Configure filter wheel for standard photometric slots
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# 6. Unpark and optionally slew to a neutral position
unpark_telescope
sleep 1
# Slew to North Celestial Pole to avoid accidentally starting on a target
slew_to_coordinates 0.0 89.0
wait_for_slew_complete 15 || true
echo "Telescope initialized."

# 7. Create the candidate list document
cat > /home/ga/Documents/extinction_targets.txt << 'EOF'
CANDIDATE CALIBRATION STARS
===========================
1. Sirius (RA 06h 45m 09s, Dec -16d 42m 58s)
2. Capella (RA 05h 16m 41s, Dec +45d 59m 53s)
3. Rigel (RA 05h 14m 32s, Dec -08d 12m 06s)
4. Procyon (RA 07h 39m 18s, Dec +05d 13m 30s)
5. Regulus (RA 10h 08m 22s, Dec +11d 58m 02s)
6. Arcturus (RA 14h 15m 40s, Dec +19d 10m 57s)
7. Vega (RA 18h 36m 56s, Dec +38d 47m 01s)
8. Altair (RA 19h 50m 47s, Dec +08d 52m 06s)
9. Deneb (RA 20h 41m 26s, Dec +45d 16m 49s)
10. Fomalhaut (RA 22h 57m 39s, Dec -29d 37m 20s)
11. Aldebaran (RA 04h 35m 55s, Dec +16d 30m 33s)
12. Spica (RA 13h 25m 11s, Dec -11d 09m 41s)

INSTRUCTIONS:
- Select 4 stars that are currently > 20 degrees Altitude.
- Capture 3 x 5s V-band LIGHT frames per star.
- Save to ~/Images/extinction/<Star_Name>/
- Produce report at ~/Documents/extinction_report.txt computing Airmass (1 / sin(Altitude)).
EOF
chown ga:ga /home/ga/Documents/extinction_targets.txt

# 8. Set CCD defaults
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 9. Ensure KStars is running and visible
ensure_kstars_running
sleep 3
maximize_kstars
focus_kstars
sleep 1

# 10. Record initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="