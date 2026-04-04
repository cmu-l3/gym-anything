#!/bin/bash
echo "=== Setting up fugitive_traffic_stop task ==="

source /workspace/scripts/task_utils.sh

# Lesson 120: ensure export script is executable after checkpoint SCP
chmod +x /workspace/tasks/fugitive_traffic_stop/export_result.sh 2>/dev/null || true

# Record baselines BEFORE agent starts to prevent seed-data false positives
BASELINE_MAX_ACTIVE_CALL=$(opencad_db_query "SELECT COALESCE(MAX(call_id),0) FROM calls")
BASELINE_MAX_HISTORY_CALL=$(opencad_db_query "SELECT COALESCE(MAX(call_id),0) FROM call_history")
BASELINE_MAX_CITATION=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM ncic_citations")
BASELINE_MAX_BOLO_PERSON=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM bolos_persons")

echo "${BASELINE_MAX_ACTIVE_CALL:-0}" | sudo tee /tmp/fts_baseline_active_call > /dev/null
echo "${BASELINE_MAX_HISTORY_CALL:-0}" | sudo tee /tmp/fts_baseline_history_call > /dev/null
echo "${BASELINE_MAX_CITATION:-0}" | sudo tee /tmp/fts_baseline_citation > /dev/null
echo "${BASELINE_MAX_BOLO_PERSON:-0}" | sudo tee /tmp/fts_baseline_bolo_person > /dev/null
sudo chmod 666 /tmp/fts_baseline_active_call /tmp/fts_baseline_history_call /tmp/fts_baseline_citation /tmp/fts_baseline_bolo_person

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
