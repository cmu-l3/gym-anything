#!/bin/bash
set -e
echo "=== Setting up galaxy_cluster_lensing_atlas task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -rf /home/ga/Lensing
rm -f /home/ga/Documents/jwst_lensing_proposal.txt
rm -f /tmp/task_result.json

# 3. Create root directory
mkdir -p /home/ga/Lensing
mkdir -p /home/ga/Documents

# 4. ERROR INJECTION: Seed a stale reference.png for Abell 1689
# The agent must overwrite this to prove they actually ran the capture script
mkdir -p /home/ga/Lensing/Abell1689
touch -t 202401010000 /home/ga/Lensing/Abell1689/reference.png 2>/dev/null || true
chown -R ga:ga /home/ga/Lensing
chown -R ga:ga /home/ga/Documents

# 5. Start INDI server and connect devices
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

# 7. Unpark telescope and slew to a neutral/wrong position (South Celestial Pole)
unpark_telescope
sleep 1
slew_to_coordinates 0.000 -89.000
wait_for_slew_complete 20
echo "Telescope parked near South Celestial Pole. Agent must slew to targets."

# 8. Reset CCD settings
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 9. Create the JWST proposal draft document
cat > /home/ga/Documents/jwst_lensing_proposal.txt << 'EOF'
JWST FOLLOW-UP PROPOSAL PREPARATION
===================================
Target List: Strong Lensing Galaxy Clusters

We need pointing confirmation CCD frames (Luminance, 60s) and sky reference
renderings for three primary targets.

TARGET 1: Abell 1689
RA: 13h 11m 30s
Dec: -01d 20m 28s

TARGET 2: Abell 2218
RA: 248.975 degrees  (Note: INDI requires Right Ascension in hours!)
Dec: +66d 12m 47s

TARGET 3: Abell 370
RA: 02h 39m 53s
Dec: -01d 34m 36s

PROCEDURE
---------
For each target:
1. Slew the telescope to the target coordinates.
2. Configure the CCD Simulator to save images locally to:
   /home/ga/Lensing/[TargetName]/ (e.g., /home/ga/Lensing/Abell1689/)
3. Take a 60-second exposure using the Luminance filter (slot 1).
4. Generate a sky reference image with a 0.2-degree field of view using
   the 'hubble' false-color palette:
   bash ~/capture_sky_view.sh /home/ga/Lensing/[TargetName]/reference.png 0.2 --palette hubble

After completing all three targets, create an observation log at:
/home/ga/Lensing/atlas_log.txt

List the final decimal RA (in hours) and Dec (in degrees) used for each pointing.
EOF

chown ga:ga /home/ga/Documents/jwst_lensing_proposal.txt

# 10. Start KStars, dismiss dialogs, maximize
ensure_kstars_running
sleep 3
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done
maximize_kstars
focus_kstars
sleep 1

# 11. Record initial state and take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Proposal doc at ~/Documents/jwst_lensing_proposal.txt"