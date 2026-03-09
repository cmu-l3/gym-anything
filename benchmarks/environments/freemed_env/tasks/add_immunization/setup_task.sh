#!/bin/bash
# Setup task: add_immunization
# Patient: Malka Hartmann (ID 12) - Synthea-generated patient
# Task: Add Td (adult) vaccine on 2024-11-15

echo "=== Setting up add_immunization task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_timestamp

# Verify patient Malka Hartmann (ID 12) exists in FreeMED
PATIENT=$(freemed_query "SELECT id, ptfname, ptlname FROM patient WHERE id=12" 2>/dev/null)
echo "Target patient: $PATIENT"

if [ -z "$PATIENT" ]; then
    echo "ERROR: Patient ID 12 (Malka Hartmann) not found!"
    exit 1
fi

# Remove any pre-existing Td vaccine on 2024-11-15 for clean state
freemed_query "DELETE FROM immunization WHERE patient=12 AND DATE(dateof)='2024-11-15'" 2>/dev/null || true

# Record initial immunization count
INITIAL=$(freemed_query "SELECT COUNT(*) FROM immunization WHERE patient=12" 2>/dev/null || echo "0")
echo "$INITIAL" > /tmp/initial_immunization_count
echo "Initial immunization count for Malka Hartmann: $INITIAL"

ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

take_screenshot /tmp/task_immunization_start.png

echo ""
echo "=== add_immunization task setup complete ==="
echo "Task: Add Td (adult) tetanus-diphtheria vaccine (2024-11-15, Lot TD2024-892) for Malka Hartmann (ID=12)"
echo "Login: admin / admin"
echo ""
