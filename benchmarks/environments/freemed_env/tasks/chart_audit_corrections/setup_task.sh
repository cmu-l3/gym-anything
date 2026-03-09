#!/bin/bash
# Setup task: chart_audit_corrections
# Patients: Malka Hartmann (ID 12), Myrtis Armstrong (ID 16), Arlie McClure (ID 17)
# Task: Fix 3 chart errors — wrong phone, missing allergy, missing diagnosis

echo "=== Setting up chart_audit_corrections ==="

source /workspace/scripts/task_utils.sh

# --- Patient 12: Malka Hartmann ---
P1=12
P2=16
P3=17

# Verify all patients exist
P1_NAME=$(freemed_query "SELECT CONCAT(ptfname,' ',ptlname) FROM patient WHERE id=$P1" 2>/dev/null)
P2_NAME=$(freemed_query "SELECT CONCAT(ptfname,' ',ptlname) FROM patient WHERE id=$P2" 2>/dev/null)
P3_NAME=$(freemed_query "SELECT CONCAT(ptfname,' ',ptlname) FROM patient WHERE id=$P3" 2>/dev/null)

echo "Patient 1: $P1_NAME (ID $P1)"
echo "Patient 2: $P2_NAME (ID $P2)"
echo "Patient 3: $P3_NAME (ID $P3)"

if [ -z "$P1_NAME" ] || [ -z "$P2_NAME" ] || [ -z "$P3_NAME" ]; then
    echo "ERROR: One or more required patients not found!"
    exit 1
fi

# --- Inject Error 1: Corrupt Malka Hartmann's phone number ---
freemed_query "UPDATE patient SET pthphone='555-0-ERROR' WHERE id=$P1" 2>/dev/null
echo "Corrupted phone for patient $P1 (Malka Hartmann)"

# --- Inject Error 2: Remove Penicillin allergy from Myrtis Armstrong ---
freemed_query "DELETE FROM allergies_atomic WHERE patient=$P2 AND allergy LIKE '%enicillin%'" 2>/dev/null
echo "Removed Penicillin allergy for patient $P2 (Myrtis Armstrong)"

# --- Inject Error 3: Remove Type 2 Diabetes from Arlie McClure's problem list ---
freemed_query "DELETE FROM current_problems WHERE ppatient=$P3 AND (problem_code LIKE '250%' OR problem LIKE '%iabet%')" 2>/dev/null
echo "Removed Diabetes diagnosis for patient $P3 (Arlie McClure)"

# Record baselines after setup
P1_PHONE=$(freemed_query "SELECT pthphone FROM patient WHERE id=$P1" 2>/dev/null)
P2_ALLERGY_COUNT=$(freemed_query "SELECT COUNT(*) FROM allergies_atomic WHERE patient=$P2" 2>/dev/null || echo "0")
P3_PROBLEM_COUNT=$(freemed_query "SELECT COUNT(*) FROM current_problems WHERE ppatient=$P3" 2>/dev/null || echo "0")

echo "$P1_PHONE" > /tmp/cac_p1_phone
echo "$P2_ALLERGY_COUNT" > /tmp/cac_p2_allergy_count
echo "$P3_PROBLEM_COUNT" > /tmp/cac_p3_problem_count

echo "Baselines — p1_phone: $P1_PHONE, p2_allergies: $P2_ALLERGY_COUNT, p3_problems: $P3_PROBLEM_COUNT"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch FreeMED
ensure_firefox_running "http://localhost/freemed/"

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
take_screenshot /tmp/chart_audit_corrections_start.png

echo ""
echo "=== Setup Complete ==="
echo "Errors injected:"
echo "  1. Malka Hartmann (ID=$P1, DOB: 1994-11-26): phone corrupted to '555-0-ERROR' → correct to 413-555-2847"
echo "  2. Myrtis Armstrong (ID=$P2, DOB: 1985-04-08): Penicillin allergy removed → add back (anaphylaxis/severe)"
echo "  3. Arlie McClure (ID=$P3, DOB: 1971-03-06): Diabetes 250.00 removed → add back (onset: 2019-03-15)"
echo "Login: admin / admin at http://localhost/freemed/"
echo ""
