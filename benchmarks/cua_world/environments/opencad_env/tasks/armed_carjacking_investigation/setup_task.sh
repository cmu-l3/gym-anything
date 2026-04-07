#!/bin/bash
echo "=== Setting up armed_carjacking_investigation task ==="

source /workspace/scripts/task_utils.sh

# Lesson 120: ensure export script is executable after checkpoint SCP
chmod +x /workspace/tasks/armed_carjacking_investigation/export_result.sh 2>/dev/null || true

# --------------------------------------------------------
# Seed three suspects with different DL statuses and criminal records.
# The agent must search NCIC to discover which one has BOTH an expired
# license AND a violent offense — that is Derek Lawson.
#
#   Marcus Vance:  DL Expired, NO warrants      (decoy: matches DL only)
#   Derek Lawson:  DL Expired, Aggravated Assault warrant (THE ANSWER)
#   Anton Reeves:  DL Valid,   Petty Theft warrant (decoy: no expired DL)
# --------------------------------------------------------

# Insert three civilians (AUTO_INCREMENT assigns IDs)
opencad_db_query "INSERT INTO ncic_names (submittedByName, submittedById, name, dob, address, gender, race, dl_status, hair_color, build, weapon_permit, deceased) VALUES
('Admin User', '1A-01', 'Marcus Vance',  '1980-05-12', '1500 Power Street, Los Santos',     'Male', 'Caucasian',                'Expired', 'Brown',  'Average',    'Unobtained', 'NO'),
('Admin User', '1A-01', 'Derek Lawson',  '1978-03-29', '742 Covenant Avenue, Los Santos',    'Male', 'Caucasian',                'Expired', 'Blonde', 'Fit',        'Unobtained', 'NO'),
('Admin User', '1A-01', 'Anton Reeves',  '1982-09-14', '309 Strawberry Avenue, Los Santos',  'Male', 'Black or African American', 'Valid',   'Black',  'Overweight', 'Unobtained', 'NO')"

# Retrieve their assigned IDs
MARCUS_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE name='Marcus Vance' ORDER BY id DESC LIMIT 1")
DEREK_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE name='Derek Lawson' ORDER BY id DESC LIMIT 1")
ANTON_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE name='Anton Reeves' ORDER BY id DESC LIMIT 1")

echo "Seeded suspects: Marcus=$MARCUS_ID, Derek=$DEREK_ID, Anton=$ANTON_ID"

# Link civilians to admin user in junction table
opencad_db_query "INSERT INTO civilian_names (user_id, names_id) VALUES (2, ${MARCUS_ID}), (2, ${DEREK_ID}), (2, ${ANTON_ID})"

# Insert warrants for Derek (violent) and Anton (non-violent decoy)
opencad_db_query "INSERT INTO ncic_warrants (expiration_date, warrant_name, issuing_agency, name_id, issued_date, status) VALUES
('2027-01-10', 'Aggravated Assault', 'Blaine County Sheriff Office', ${DEREK_ID}, '2025-01-10', 'Active'),
('2027-03-05', 'Petty Theft',        'Los Santos Police Department', ${ANTON_ID}, '2025-03-05', 'Active')"

# --------------------------------------------------------
# Record baselines BEFORE agent starts
# --------------------------------------------------------
BASELINE_MAX_ACTIVE_CALL=$(opencad_db_query "SELECT COALESCE(MAX(call_id),0) FROM calls")
BASELINE_MAX_HISTORY_CALL=$(opencad_db_query "SELECT COALESCE(MAX(call_id),0) FROM call_history")
BASELINE_MAX_WARRANT=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM ncic_warrants")
BASELINE_MAX_CITATION=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM ncic_citations")
BASELINE_MAX_BOLO_VEH=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM bolos_vehicles")
BASELINE_MAX_BOLO_PER=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM bolos_persons")
BASELINE_MAX_NCIC_NAME=$(opencad_db_query "SELECT COALESCE(MAX(id),0) FROM ncic_names")

echo "${BASELINE_MAX_ACTIVE_CALL:-0}" | sudo tee /tmp/aci_baseline_active_call > /dev/null
echo "${BASELINE_MAX_HISTORY_CALL:-0}" | sudo tee /tmp/aci_baseline_history_call > /dev/null
echo "${BASELINE_MAX_WARRANT:-0}" | sudo tee /tmp/aci_baseline_warrant > /dev/null
echo "${BASELINE_MAX_CITATION:-0}" | sudo tee /tmp/aci_baseline_citation > /dev/null
echo "${BASELINE_MAX_BOLO_VEH:-0}" | sudo tee /tmp/aci_baseline_bolo_veh > /dev/null
echo "${BASELINE_MAX_BOLO_PER:-0}" | sudo tee /tmp/aci_baseline_bolo_per > /dev/null
echo "${BASELINE_MAX_NCIC_NAME:-0}" | sudo tee /tmp/aci_baseline_ncic_name > /dev/null
echo "${DEREK_ID:-0}" | sudo tee /tmp/aci_derek_id > /dev/null

sudo chmod 666 /tmp/aci_baseline_active_call /tmp/aci_baseline_history_call \
    /tmp/aci_baseline_warrant /tmp/aci_baseline_citation /tmp/aci_baseline_bolo_veh \
    /tmp/aci_baseline_bolo_per /tmp/aci_baseline_ncic_name /tmp/aci_derek_id

# --------------------------------------------------------
# Relaunch Firefox
# --------------------------------------------------------
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
