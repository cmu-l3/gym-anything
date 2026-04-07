#!/bin/bash
echo "=== Setting up carjacking_incident_full_response task ==="

source /workspace/scripts/task_utils.sh

# Ensure export script is executable after checkpoint SCP
chmod +x /workspace/tasks/carjacking_incident_full_response/export_result.sh 2>/dev/null || true

# --- CLEAN PRIOR RUN ARTIFACTS ---
# Remove any Diego Ramirez records from previous runs
opencad_db_query "DELETE FROM ncic_plates WHERE name_id IN (SELECT id FROM ncic_names WHERE LOWER(name) LIKE '%diego%ramirez%')" 2>/dev/null || true
opencad_db_query "DELETE FROM civilian_names WHERE names_id IN (SELECT id FROM ncic_names WHERE LOWER(name) LIKE '%diego%ramirez%')" 2>/dev/null || true
opencad_db_query "DELETE FROM ncic_names WHERE LOWER(name) LIKE '%diego%ramirez%'" 2>/dev/null || true
# Also clean by plate in case civilian was created with different name
opencad_db_query "DELETE FROM ncic_plates WHERE UPPER(REPLACE(veh_plate,'-','')) LIKE '%DGR2247%'" 2>/dev/null || true

# --- RECORD BASELINES ---
# Snapshot MAX(id) for each relevant table BEFORE agent starts
BASELINE_MAX_NCIC_NAME=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM ncic_names")
BASELINE_MAX_NCIC_PLATE=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM ncic_plates")
BASELINE_MAX_ACTIVE_CALL=$(opencad_db_query "SELECT COALESCE(MAX(call_id),0) FROM calls")
BASELINE_MAX_HISTORY_CALL=$(opencad_db_query "SELECT COALESCE(MAX(call_id),0) FROM call_history")
BASELINE_MAX_BOLO_VEHICLE=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM bolos_vehicles")
BASELINE_MAX_BOLO_PERSON=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM bolos_persons")
BASELINE_MAX_CITATION=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM ncic_citations")

echo "${BASELINE_MAX_NCIC_NAME:-0}" | sudo tee /tmp/cifr_baseline_ncic_name > /dev/null
echo "${BASELINE_MAX_NCIC_PLATE:-0}" | sudo tee /tmp/cifr_baseline_ncic_plate > /dev/null
echo "${BASELINE_MAX_ACTIVE_CALL:-0}" | sudo tee /tmp/cifr_baseline_active_call > /dev/null
echo "${BASELINE_MAX_HISTORY_CALL:-0}" | sudo tee /tmp/cifr_baseline_history_call > /dev/null
echo "${BASELINE_MAX_BOLO_VEHICLE:-0}" | sudo tee /tmp/cifr_baseline_bolo_vehicle > /dev/null
echo "${BASELINE_MAX_BOLO_PERSON:-0}" | sudo tee /tmp/cifr_baseline_bolo_person > /dev/null
echo "${BASELINE_MAX_CITATION:-0}" | sudo tee /tmp/cifr_baseline_citation > /dev/null
sudo chmod 666 /tmp/cifr_baseline_ncic_name /tmp/cifr_baseline_ncic_plate /tmp/cifr_baseline_active_call /tmp/cifr_baseline_history_call /tmp/cifr_baseline_bolo_vehicle /tmp/cifr_baseline_bolo_person /tmp/cifr_baseline_citation

# --- RELAUNCH FIREFOX ---
rm -f /home/ga/.mozilla/firefox/default-release/lock /home/ga/.mozilla/firefox/default-release/.parentlock 2>/dev/null || true
rm -f /home/ga/snap/firefox/common/.mozilla/firefox/*/lock /home/ga/snap/firefox/common/.mozilla/firefox/*/.parentlock 2>/dev/null || true
pkill -9 -f firefox 2>/dev/null || true
sleep 2
DISPLAY=:1 firefox "http://localhost/index.php" &
sleep 10

# Dismiss Firefox popups
DISPLAY=:1 wmctrl -c "Make the Firefox" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Focus and maximize
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|OpenCAD" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

take_screenshot /tmp/task_initial.png
echo "=== Task setup complete ==="
