#!/bin/bash
set -e
echo "=== Setting up snr_multiwavelength_correlation task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/SNR
rm -f /home/ga/Documents/snr_research_plan.txt
rm -f /home/ga/Documents/snr_correlation_report.txt
rm -f /tmp/task_result.json

# 3. Create root directories
mkdir -p /home/ga/Images/SNR
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/SNR
chown -R ga:ga /home/ga/Documents

# 4. ERROR INJECTION: Create stale optical frames for Crab to ensure the agent doesn't re-use old data
mkdir -p /home/ga/Images/SNR/Crab/optical
touch -t 202401010000 /home/ga/Images/SNR/Crab/optical/old_crab_ha_001.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/SNR/Crab/optical/old_crab_ha_002.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/SNR/Crab/optical/old_crab_ha_003.fits 2>/dev/null || true
chown -R ga:ga /home/ga/Images/SNR/Crab

# 5. Start INDI server and connect devices
ensure_indi_running
sleep 2
connect_all_devices

# 6. Configure filter wheel for standard and narrowband slots
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=SII" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=Ha" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_6=OIII" 2>/dev/null || true
sleep 1

# 7. Unpark telescope and slew to a neutral/wrong position (South Galactic Pole)
unpark_telescope
sleep 1
slew_to_coordinates 0.85 -27.15
wait_for_slew_complete 20
echo "Telescope pointed to South Galactic Pole (away from SNR targets)."

# 8. Reset CCD settings
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 9. Create the research plan document
cat > /home/ga/Documents/snr_research_plan.txt << 'EOF'
MULTI-WAVELENGTH SUPERNOVA REMNANT OBSERVING PLAN
=================================================
Prepared by: High-Energy Astrophysics Group

OBJECTIVES
----------
Correlate optical narrowband emissions (H-alpha and OIII) with thermal dust 
and high-energy signatures across three historical supernova remnants.

TARGET LIST
-----------
1. Tycho (SN 1572)
   RA: 00h 25m 18s
   Dec: +64d 09m 00s (J2000)
   
2. Crab Nebula (M1)
   RA: 05h 34m 31s
   Dec: +22d 00m 52s (J2000)
   
3. Cas A (Cassiopeia A)
   RA: 23h 23m 24s
   Dec: +58d 48m 54s (J2000)

DATA ACQUISITION PROTOCOL
-------------------------
For EACH of the three targets, you must execute the following protocol.
Ensure you organize files strictly into per-target directories:
  /home/ga/Images/SNR/<Target_Name>/optical/
  /home/ga/Images/SNR/<Target_Name>/survey/

(Note: Discard/ignore any old files from previous observers. Only new data counts).

PART A: OPTICAL IMAGING
1. Slew the telescope to the target.
2. Set the CCD upload directory to the target's optical folder.
3. Select H-alpha filter (Slot 5).
4. Capture >=3 LIGHT frames at 60 seconds exposure each.
5. Select OIII filter (Slot 6).
6. Capture >=3 LIGHT frames at 60 seconds exposure each.

PART B: SURVEY CONTEXT MAPS
Generate two analogous survey charts simulating multi-wavelength bands at 0.5 degrees FOV.
Execute these commands via terminal while the telescope is pointed at the target:

1. Thermal Dust Map:
   bash ~/capture_sky_view.sh /home/ga/Images/SNR/<Target_Name>/survey/thermal_dust.png 0.5 --palette heat

2. High-Energy Map:
   bash ~/capture_sky_view.sh /home/ga/Images/SNR/<Target_Name>/survey/high_energy.png 0.5 --palette cool

DELIVERABLES
------------
- The optical and survey directories correctly populated for all 3 targets.
- A summary report file created at ~/Documents/snr_correlation_report.txt
  confirming that data for Tycho, Crab, and Cas A was successfully acquired.
EOF
chown ga:ga /home/ga/Documents/snr_research_plan.txt

# 10. Ensure KStars is running
ensure_kstars_running
sleep 3
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done
maximize_kstars
focus_kstars
sleep 1

# 11. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Observing plan at ~/Documents/snr_research_plan.txt"