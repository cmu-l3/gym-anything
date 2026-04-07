#!/bin/bash
set -e
echo "=== Setting up arp_interacting_galaxies_survey task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -rf /home/ga/Images/arp_survey
rm -f /home/ga/Documents/arp_merger_targets.txt
rm -f /home/ga/Documents/arp_survey_log.json
rm -f /tmp/task_result.json

# 3. Create survey base directory
mkdir -p /home/ga/Images/arp_survey
mkdir -p /home/ga/Documents

# 4. ERROR INJECTION: Seed stale data from an old (not requested) target
mkdir -p /home/ga/Images/arp_survey/arp220
# Pre-date these files so the agent/verifier can distinguish them
touch -t 202401010000 /home/ga/Images/arp_survey/arp220/morphology_arp220.png 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/arp_survey/arp220/sim_001.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/arp_survey/arp220/sim_002.fits 2>/dev/null || true
touch -t 202401010000 /home/ga/Images/arp_survey/arp220/sim_003.fits 2>/dev/null || true

chown -R ga:ga /home/ga/Images/arp_survey
chown -R ga:ga /home/ga/Documents

# 5. Start INDI server and connect
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

# 7. Unpark telescope and slew to an unrelated position (M31)
unpark_telescope
sleep 1
slew_to_coordinates 0.712 41.269
wait_for_slew_complete 20
echo "Telescope at M31 (wrong target). Agent must slew to the Arp targets."

# 8. Reset CCD upload settings
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 9. Create the survey target list document
cat > /home/ga/Documents/arp_merger_targets.txt << 'EOF'
ARP INTERACTING GALAXIES SURVEY
===============================

TARGETS
-------
1. Arp 244 (Antennae Galaxies)
   RA: 12h 01m 53s
   Dec: -18d 52m 10s (J2000)

2. Arp 273 (Rose Galaxy)
   RA: 02h 21m 28s
   Dec: +39d 22m 32s (J2000)

3. Arp 242 (Mice Galaxies)
   RA: 12h 46m 10s
   Dec: +26d 23m 04s (J2000)

4. Arp 81 (NGC 6621)
   RA: 18h 12m 55s
   Dec: +68d 21m 48s (J2000)

OBSERVING REQUIREMENTS
----------------------
For each target above:
1. Set the Filter Wheel to Slot 1 (Luminance/Clear)
2. Slew telescope to the target coordinates
3. Set CCD upload directory to: /home/ga/Images/arp_survey/<target_name>/ (e.g., arp244, arp273)
4. Take exactly 3 LIGHT frames of 120 seconds each
5. Capture a morphology sky view with 0.5 degree FOV and vibrant palette:
   Example: bash ~/capture_sky_view.sh /home/ga/Images/arp_survey/arp244/morphology_arp244.png 0.5 --palette vibrant

LOGGING REQUIREMENTS
--------------------
Generate a JSON log file at /home/ga/Documents/arp_survey_log.json
This file must contain an array or dictionary of the targets successfully observed.
(e.g., ["arp244", "arp273", "arp242", "arp81"])
EOF

chown ga:ga /home/ga/Documents/arp_merger_targets.txt

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

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="