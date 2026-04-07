#!/bin/bash
set -e
echo "=== Setting up deepsky_outreach_gallery task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# 2. Clean up previous run artifacts and create root dir
rm -rf /home/ga/Outreach
rm -f /tmp/task_result.json
mkdir -p /home/ga/Outreach
chown -R ga:ga /home/ga/Outreach

# 3. Ensure INDI server is running with all simulators
ensure_indi_running
sleep 2
connect_all_devices

# 4. Unpark telescope and slew to WRONG position (agent must slew to targets)
unpark_telescope
sleep 1
# Point near Polaris - far from all targets
slew_to_coordinates 2.5 89.0
wait_for_slew_complete 15
echo "Telescope initialized near Polaris. Agent must slew to targets."

# 5. Reset CCD to defaults
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# 6. Mark start in indiserver log for slew counting
echo "=== TASK_START ===" >> /tmp/indiserver.log

# 7. Ensure KStars is running and maximized
ensure_kstars_running
sleep 3

for i in 1 2; do
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
done

maximize_kstars
focus_kstars
sleep 1

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Telescope initialized at RA=2.5, Dec=89.0"
echo "Outreach directory prepared."