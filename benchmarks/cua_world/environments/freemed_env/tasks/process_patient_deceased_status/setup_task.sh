#!/bin/bash
echo "=== Setting up process_patient_deceased_status task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

echo "Seeding patient Arthur Pendelton..."
# Insert patient Arthur Pendelton if he doesn't already exist
mysql -u freemed -pfreemed freemed -e "
INSERT INTO patient (ptfname, ptlname, ptdob) 
SELECT 'Arthur', 'Pendelton', '1940-05-12' 
FROM DUAL 
WHERE NOT EXISTS (SELECT 1 FROM patient WHERE ptfname='Arthur' AND ptlname='Pendelton');
" 2>/dev/null

# Ensure the patient is alive (clean state) before task begins
# FreeMED uses ptdod for Date of Death. We set it to NULL.
mysql -u freemed -pfreemed freemed -e "
UPDATE patient SET ptdod=NULL WHERE ptfname='Arthur' AND ptlname='Pendelton';
" 2>/dev/null || true

# Check if patient was seeded properly
PATIENT_COUNT=$(mysql -u freemed -pfreemed freemed -N -e "SELECT COUNT(*) FROM patient WHERE ptfname='Arthur' AND ptlname='Pendelton';" 2>/dev/null || echo "0")
echo "Initial patient 'Arthur Pendelton' count: $PATIENT_COUNT"

# Ensure Firefox is running and navigated to FreeMED
ensure_firefox_running "http://localhost/freemed/"

# Focus and maximize the window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot showing starting state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target: Patient Arthur Pendelton (DOB: 1940-05-12)"
echo "Action required: Edit demographics, mark Deceased, set Date of Death to 2026-03-01"