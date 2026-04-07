#!/bin/bash
set -e
echo "=== Setting up robotic_too_pipeline_scripting task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Clean up previous run artifacts
rm -f /home/ga/too_capture.sh
rm -rf /home/ga/Images/too_alerts
rm -f /home/ga/Documents/too_script_spec.txt
rm -f /tmp/task_result.json

mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Ensure INDI server is running with all simulators
ensure_indi_running
sleep 2
connect_all_devices

# Configure filter wheel with standard BVRI slots
indi_setprop "Filter Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=L" 2>/dev/null || true
indi_setprop "Filter Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=I" 2>/dev/null || true
sleep 1

# Park telescope to start in a safe state
park_telescope
sleep 1

# Reset CCD to defaults
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# Create the campaign brief document
cat > /home/ga/Documents/too_script_spec.txt << 'EOF'
ROBOTIC TARGET OF OPPORTUNITY (ToO) PIPELINE SCRIPTING
======================================================
Priority: HIGH
Context: The observatory needs an automated bash script to respond to Target of Opportunity (ToO) alerts (like Gamma-Ray Bursts) without human intervention.

REQUIREMENTS
------------
You must write a bash script at `/home/ga/too_capture.sh`.
The script must accept exactly 5 positional arguments in this order:
  $1: RA_HOURS
  $2: DEC_DEGREES
  $3: FILTER_SLOT
  $4: EXPOSURE_SECONDS
  $5: UPLOAD_DIR

The script must perform the following actions using INDI properties (`indi_setprop` and `indi_getprop`):
1. Configure the CCD to save images locally to UPLOAD_DIR.
   (Hint: set CCD Simulator.UPLOAD_MODE.UPLOAD_LOCAL=On and CCD Simulator.UPLOAD_SETTINGS.UPLOAD_DIR)
2. Unpark the telescope.
   (Hint: Telescope Simulator.TELESCOPE_PARK.UNPARK=On)
3. Set the filter wheel to FILTER_SLOT and **wait** for the filter change to complete.
   (Hint: Filter Simulator.FILTER_SLOT.FILTER_SLOT_VALUE)
4. Slew the telescope to the specified RA and Dec, and **wait** for the slew to complete.
   (Hint: set Telescope Simulator.ON_COORD_SET.TRACK=On, then Telescope Simulator.EQUATORIAL_EOD_COORD.RA;DEC)
5. Start a LIGHT frame exposure for EXPOSURE_SECONDS and **wait** for the exposure/download to finish.
   (Hint: set CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On, then CCD Simulator.CCD_EXPOSURE.CCD_EXPOSURE_VALUE)
6. Issue the command to PARK the telescope at the end of the script to secure the observatory.
   (Hint: Telescope Simulator.TELESCOPE_PARK.PARK=On)

POLLING REQUIREMENT
-------------------
Because hardware commands are asynchronous, your script MUST contain `while` or `until` loops that poll the device states using `indi_getprop`. 
- For example, Slew state: wait until `Telescope Simulator.EQUATORIAL_EOD_COORD._STATE` becomes 'Ok'
- For example, Exposure value: wait until `CCD Simulator.CCD_EXPOSURE.CCD_EXPOSURE_VALUE` returns to '0' (or its _STATE becomes 'Ok')

TESTING
-------
Test your script by executing it to capture the historic GRB 221009A.
Target: GRB 221009A
RA: 19.2175 (hours)
Dec: 19.7733 (degrees)
Filter: Slot 4 (R-band)
Exposure: 120 seconds
Directory: /home/ga/Images/too_alerts/GRB221009A/

Example execution:
bash /home/ga/too_capture.sh 19.2175 19.7733 4 120 /home/ga/Images/too_alerts/GRB221009A/

Ensure you make the script executable (`chmod +x /home/ga/too_capture.sh`) before testing.
EOF
chown ga:ga /home/ga/Documents/too_script_spec.txt

# Ensure KStars is running and maximized
ensure_kstars_running
sleep 3
for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done
maximize_kstars
focus_kstars
sleep 1

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="