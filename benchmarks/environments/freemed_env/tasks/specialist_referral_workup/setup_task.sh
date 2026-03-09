#!/bin/bash
# Setup task: specialist_referral_workup
# Patient: Kelle Crist (ID 9, DOB 2002-10-18, F)
# Task: Migraine workup — diagnosis + allergy + Rx + note + neurology referral

echo "=== Setting up specialist_referral_workup ==="

source /workspace/scripts/task_utils.sh

PATIENT_ID=9

# Verify target patient exists
PATIENT=$(freemed_query "SELECT id, ptfname, ptlname FROM patient WHERE id=$PATIENT_ID" 2>/dev/null)
echo "Target patient: $PATIENT"

if [ -z "$PATIENT" ]; then
    echo "ERROR: Patient ID $PATIENT_ID (Kelle Crist) not found!"
    exit 1
fi

# Clear any pre-existing relevant data
freemed_query "DELETE FROM current_problems WHERE ppatient=$PATIENT_ID AND (problem_code LIKE '346%' OR problem LIKE '%migrain%')" 2>/dev/null || true
freemed_query "DELETE FROM allergies_atomic WHERE patient=$PATIENT_ID AND allergy LIKE '%Aspirin%'" 2>/dev/null || true
freemed_query "DELETE FROM medications WHERE mpatient=$PATIENT_ID AND mdrugs LIKE '%Sumatriptan%'" 2>/dev/null || true
freemed_query "DELETE FROM pnotes WHERE pnotespat=$PATIENT_ID" 2>/dev/null || true
freemed_query "DELETE FROM referrals WHERE patient=$PATIENT_ID AND specialty LIKE '%Neuro%'" 2>/dev/null || true

echo "Cleared pre-existing data for patient $PATIENT_ID"

# Record initial counts
INITIAL_PROBLEMS=$(freemed_query "SELECT COUNT(*) FROM current_problems WHERE ppatient=$PATIENT_ID" 2>/dev/null || echo "0")
INITIAL_ALLERGIES=$(freemed_query "SELECT COUNT(*) FROM allergies_atomic WHERE patient=$PATIENT_ID" 2>/dev/null || echo "0")
INITIAL_MEDS=$(freemed_query "SELECT COUNT(*) FROM medications WHERE mpatient=$PATIENT_ID" 2>/dev/null || echo "0")
INITIAL_NOTES=$(freemed_query "SELECT COUNT(*) FROM pnotes WHERE pnotespat=$PATIENT_ID" 2>/dev/null || echo "0")
INITIAL_REFERRALS=$(freemed_query "SELECT COUNT(*) FROM referrals WHERE patient=$PATIENT_ID" 2>/dev/null || echo "0")

echo "$INITIAL_PROBLEMS" > /tmp/srw_initial_problems
echo "$INITIAL_ALLERGIES" > /tmp/srw_initial_allergies
echo "$INITIAL_MEDS" > /tmp/srw_initial_meds
echo "$INITIAL_NOTES" > /tmp/srw_initial_notes
echo "$INITIAL_REFERRALS" > /tmp/srw_initial_referrals

echo "Initial counts — problems: $INITIAL_PROBLEMS, allergies: $INITIAL_ALLERGIES, meds: $INITIAL_MEDS, notes: $INITIAL_NOTES, referrals: $INITIAL_REFERRALS"

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
take_screenshot /tmp/specialist_referral_workup_start.png

echo ""
echo "=== Setup Complete ==="
echo "Patient: Kelle Crist (ID=$PATIENT_ID, DOB: 2002-10-18)"
echo "Task: Add migraine dx + Aspirin allergy + Sumatriptan Rx + note + Neurology referral"
echo "Login: admin / admin at http://localhost/freemed/"
echo ""
