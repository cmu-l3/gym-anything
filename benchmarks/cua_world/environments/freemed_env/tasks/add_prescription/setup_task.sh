#!/bin/bash
echo "=== Setting up Add Prescription Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create the patient Margaret Thompson if she doesn't exist
echo "Ensuring patient Margaret Thompson exists in DB..."
mysql -u freemed -pfreemed freemed -e "
INSERT IGNORE INTO patient (ptfname, ptmname, ptlname, ptdob, ptsex, ptaddr1, ptcity, ptstate, ptzip)
VALUES ('Margaret', 'A', 'Thompson', '1966-05-14', 'f', '742 Evergreen Terrace', 'Springfield', 'IL', '62704');
" 2>/dev/null

# Get Patient ID
PAT_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Margaret' AND ptlname='Thompson' LIMIT 1")
echo "Patient ID: $PAT_ID"
echo "$PAT_ID" > /tmp/target_patient_id.txt

# Remove any pre-existing Lisinopril prescriptions for this patient to ensure a clean state
mysql -u freemed -pfreemed freemed -e "DELETE FROM rx WHERE rxpatient='$PAT_ID' AND rxdrug LIKE '%Lisinopril%';" 2>/dev/null || true

# Record initial prescription count for this patient
INITIAL_RX_COUNT=$(freemed_query "SELECT COUNT(*) FROM rx WHERE rxpatient='$PAT_ID'" 2>/dev/null || echo "0")
echo "$INITIAL_RX_COUNT" > /tmp/initial_rx_count.txt
echo "Initial prescription count: $INITIAL_RX_COUNT"

# Ensure Firefox is running and at FreeMED login
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_setup_start.png

echo "=== Add Prescription Task Setup Complete ==="
echo "Target Patient: Margaret Thompson"
echo "Medication: Lisinopril 10mg"
echo "Login: admin / admin"