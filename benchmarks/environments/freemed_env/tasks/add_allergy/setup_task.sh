#!/bin/bash
# Setup task: add_allergy
# Patient: Myrtis Armstrong (ID 16) - Synthea-generated patient
# Synthea data shows she has Ibuprofen allergy

echo "=== Setting up add_allergy task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Verify patient Myrtis Armstrong (ID 16)
PATIENT=$(freemed_query "SELECT id, ptfname, ptlname FROM patient WHERE id=16" 2>/dev/null)
echo "Target patient: $PATIENT"

if [ -z "$PATIENT" ]; then
    echo "ERROR: Patient ID 16 (Myrtis Armstrong) not found!"
    exit 1
fi

# Remove any pre-existing Ibuprofen allergy for clean state
freemed_query "DELETE FROM allergies_atomic WHERE patient=16 AND allergy LIKE '%Ibuprofen%'" 2>/dev/null || true
freemed_query "DELETE FROM allergies WHERE patient=16 AND allergies LIKE '%Ibuprofen%'" 2>/dev/null || true

# Record initial allergy count
INITIAL=$(freemed_query "SELECT COUNT(*) FROM allergies_atomic WHERE patient=16" 2>/dev/null || echo "0")
echo "$INITIAL" > /tmp/initial_allergy_count
echo "Initial allergy count for Myrtis: $INITIAL"

ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_allergy_start.png

echo ""
echo "=== add_allergy task setup complete ==="
echo "Task: Add Ibuprofen allergy (Skin rash and hives, Moderate) for Myrtis Armstrong (ID=16)"
echo "Login: admin / admin"
echo ""
