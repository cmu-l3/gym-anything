#!/bin/bash
echo "=== Setting up new_resident_full_processing task ==="

source /workspace/scripts/task_utils.sh

# Lesson 120: ensure export script is executable after checkpoint SCP
chmod +x /workspace/tasks/new_resident_full_processing/export_result.sh 2>/dev/null || true

# Record baselines BEFORE agent starts
BASELINE_MAX_NCIC_NAME=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM ncic_names")
BASELINE_MAX_NCIC_PLATE=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM ncic_plates")
BASELINE_MAX_NCIC_WARRANT=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM ncic_warrants")

echo "${BASELINE_MAX_NCIC_NAME:-0}" | sudo tee /tmp/nrfp_baseline_ncic_name > /dev/null
echo "${BASELINE_MAX_NCIC_PLATE:-0}" | sudo tee /tmp/nrfp_baseline_ncic_plate > /dev/null
echo "${BASELINE_MAX_NCIC_WARRANT:-0}" | sudo tee /tmp/nrfp_baseline_ncic_warrant > /dev/null
sudo chmod 666 /tmp/nrfp_baseline_ncic_name /tmp/nrfp_baseline_ncic_plate /tmp/nrfp_baseline_ncic_warrant

# Relaunch Firefox
rm -f /home/ga/.mozilla/firefox/default-release/lock /home/ga/.mozilla/firefox/default-release/.parentlock 2>/dev/null || true
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/lock /home/ga/snap/firefox/common/.mozilla/firefox/*/.parentlock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2
DISPLAY=:1 firefox "http://localhost/index.php" &
sleep 10

DISPLAY=:1 wmctrl -c "Make the Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

take_screenshot /tmp/task_initial.png
echo "=== Task setup complete ==="
