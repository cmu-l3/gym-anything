#!/bin/bash
# setup_task.sh — oc_tb_contact_trace: TB Contact Tracing
#
# Prepares a clean starting state for the TB contact tracing task.
# Three new patients must be registered by the agent (not pre-seeded):
#   1. Kofi Asante     (M, 1988-07-22, GH)
#   2. Rania Aziz      (F, 1975-03-10, EG)
#   3. Dimitri Papadopoulos (M, 1962-11-30, GR)
#
# For each: register patient + order MALAR lab (TB AFB smear) + schedule follow-up

set -euo pipefail
echo "=== Setting up TB Contact Tracing task ==="

source /workspace/scripts/task_utils.sh

record_task_start /tmp/task_start_timestamp

# ---------------------------------------------------------------
# Remove any prior entries for the 3 TB contacts (for reruns)
# ---------------------------------------------------------------
echo "Cleaning up any prior TB contact registrations..."

for FNAME in "KOFI" "RANIA" "DIMITRI"; do
    case "$FNAME" in
        "KOFI") LNAME="ASANTE" ;;
        "RANIA") LNAME="AZIZ" ;;
        "DIMITRI") LNAME="PAPADOPOULOS" ;;
    esac
    EXISTING_ID=$(admin_query "SELECT personid FROM adminview WHERE firstname='$FNAME' AND lastname='$LNAME' LIMIT 1" | head -1 | tr -d '[:space:]')
    if [ -n "$EXISTING_ID" ]; then
        echo "  Removing prior entry for $FNAME $LNAME (ID=$EXISTING_ID)..."
        admin_query "DELETE FROM adminprivate WHERE personid='$EXISTING_ID'" 2>/dev/null || true
        admin_query "DELETE FROM adminview WHERE personid='$EXISTING_ID'" 2>/dev/null || true
        clinical_query "DELETE FROM healthrecord WHERE personId='$EXISTING_ID'" 2>/dev/null || true
        clinical_query "DELETE FROM requestedlabanalyses WHERE patientid='$EXISTING_ID'" 2>/dev/null || true
        clinical_query "DELETE FROM oc_planning WHERE OC_PLANNING_PATIENTID='$EXISTING_ID'" 2>/dev/null || true
    fi
done

# ---------------------------------------------------------------
# Ensure MALAR lab analysis code exists
# ---------------------------------------------------------------
MALAR_COUNT=$(clinical_query "SELECT COUNT(*) FROM labanalysis WHERE labcode='MALAR'" | tr -d '[:space:]')
if [ "$MALAR_COUNT" = "0" ]; then
    echo "MALAR lab code missing — re-seeding..."
    /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root < /workspace/config/seed_data.sql 2>/dev/null || true
fi

# ---------------------------------------------------------------
# Record baseline counts for verifier
# ---------------------------------------------------------------
INITIAL_PATIENT_COUNT=$(admin_query "SELECT COUNT(*) FROM adminview" | tr -d '[:space:]')
INITIAL_LAB_COUNT=$(clinical_query "SELECT COUNT(*) FROM requestedlabanalyses" | tr -d '[:space:]')
INITIAL_PLAN_COUNT=$(clinical_query "SELECT COUNT(*) FROM oc_planning" | tr -d '[:space:]')

echo "$INITIAL_PATIENT_COUNT" > /tmp/tb_trace_baseline_patients
echo "$INITIAL_LAB_COUNT"     > /tmp/tb_trace_baseline_labs
echo "$INITIAL_PLAN_COUNT"    > /tmp/tb_trace_baseline_plan
date +%s > /tmp/tb_trace_start_ts

echo "Baseline counts:"
echo "  Patients: $INITIAL_PATIENT_COUNT"
echo "  Lab requests: $INITIAL_LAB_COUNT"
echo "  Appointments: $INITIAL_PLAN_COUNT"

# ---------------------------------------------------------------
# Launch browser
# ---------------------------------------------------------------
ensure_openclinic_browser "http://localhost:10088/openclinic"
navigate_to_url "http://localhost:10088/openclinic"
sleep 3

take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== TB Contact Tracing task ready ==="
echo ""
echo "Three TB contacts to register and process:"
echo ""
echo "  Contact 1: Kofi Asante"
echo "    DOB: 1988-07-22, Male, Country: GH (Ghana)"
echo ""
echo "  Contact 2: Rania Aziz"
echo "    DOB: 1975-03-10, Female, Country: EG (Egypt)"
echo ""
echo "  Contact 3: Dimitri Papadopoulos"
echo "    DOB: 1962-11-30, Male, Country: GR (Greece)"
echo ""
echo "For EACH contact:"
echo "  a) Register as new patient"
echo "  b) Order MALAR lab test (TB AFB smear)"
echo "  c) Schedule follow-up appointment"
echo ""
echo "Login: username=4, password=openclinic"
