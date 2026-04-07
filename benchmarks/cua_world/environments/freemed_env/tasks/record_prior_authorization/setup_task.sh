#!/bin/bash
echo "=== Setting up record_prior_authorization task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# 1. Ensure the patient 'Robert Johnson' exists in the database
echo "Verifying patient Robert Johnson..."
PATIENT_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Robert' AND ptlname='Johnson' LIMIT 1" 2>/dev/null)

if [ -z "$PATIENT_ID" ]; then
    echo "Patient not found. Creating Robert Johnson..."
    freemed_query "INSERT INTO patient (ptfname, ptlname, ptdob, ptsex) VALUES ('Robert', 'Johnson', '1982-05-10', '1')" 2>/dev/null
    PATIENT_ID=$(freemed_query "SELECT id FROM patient WHERE ptfname='Robert' AND ptlname='Johnson' LIMIT 1" 2>/dev/null)
fi

echo "Patient ID for Robert Johnson: $PATIENT_ID"
echo "$PATIENT_ID" > /tmp/target_patient_id

# 2. Clean up any existing matching authorizations to ensure a perfectly clean state
freemed_query "DELETE FROM authorizations WHERE authnum='AUTH-2025-KMR-90412'" 2>/dev/null || true

# 3. Record initial database state for verification comparison
INITIAL_COUNT=$(freemed_query "SELECT COUNT(*) FROM authorizations WHERE authpatient='$PATIENT_ID'" 2>/dev/null || echo "0")
INITIAL_MAX_ID=$(freemed_query "SELECT MAX(id) FROM authorizations" 2>/dev/null || echo "0")
[ "$INITIAL_MAX_ID" = "NULL" ] && INITIAL_MAX_ID=0

echo "$INITIAL_COUNT" > /tmp/initial_auth_count
echo "$INITIAL_MAX_ID" > /tmp/initial_max_auth_id
echo "Initial authorization count for patient: $INITIAL_COUNT (Max DB ID: $INITIAL_MAX_ID)"

# 4. Launch FreeMED in Firefox
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    # Maximize window explicitly for the agent
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# 5. Take initial screenshot as evidence
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="