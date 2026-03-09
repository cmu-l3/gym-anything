#!/bin/bash
# setup_task.sh — oc_complex_intake: Complex Patient Transfer Intake
#
# Task: Agent must complete a 5-step patient intake for Amara Nwosu
# (new patient, not pre-registered). Steps:
#   1. Register patient (demographics)
#   2. Create clinical encounter
#   3. Add 2 chronic medications (Metformin, Amlodipine)
#   4. Order 2 lab tests (HbA1c, CREAT)
#   5. Schedule follow-up appointment

set -euo pipefail
echo "=== Setting up Complex Patient Transfer Intake task ==="

source /workspace/scripts/task_utils.sh

record_task_start /tmp/task_start_timestamp

# ---------------------------------------------------------------
# Remove any pre-existing Amara Nwosu registration (for reruns)
# ---------------------------------------------------------------
echo "Cleaning up any prior Amara Nwosu entry..."
EXISTING_ID=$(admin_query "SELECT personid FROM adminview WHERE firstname='AMARA' AND lastname='NWOSU' LIMIT 1" | head -1 | tr -d '[:space:]')
if [ -n "$EXISTING_ID" ]; then
    echo "Found existing entry for Amara Nwosu (ID=$EXISTING_ID) — removing..."
    admin_query "DELETE FROM adminprivate WHERE personid='$EXISTING_ID'" 2>/dev/null || true
    admin_query "DELETE FROM adminview WHERE personid='$EXISTING_ID'" 2>/dev/null || true
    clinical_query "DELETE FROM healthrecord WHERE personId='$EXISTING_ID'" 2>/dev/null || true
    clinical_query "DELETE FROM oc_chronicmedications WHERE OC_CHRONICMED_PATIENTID='$EXISTING_ID'" 2>/dev/null || true
    clinical_query "DELETE FROM requestedlabanalyses WHERE patientid='$EXISTING_ID'" 2>/dev/null || true
    clinical_query "DELETE FROM oc_planning WHERE OC_PLANNING_PATIENTID='$EXISTING_ID'" 2>/dev/null || true
    echo "Cleanup complete for Amara Nwosu (ID=$EXISTING_ID)"
fi

# ---------------------------------------------------------------
# Ensure required medications exist in the catalog
# ---------------------------------------------------------------
for OID in 9002 9004; do
    CNT=$(clinical_query "SELECT COUNT(*) FROM oc_products WHERE OC_PRODUCT_OBJECTID=$OID" | tr -d '[:space:]')
    if [ "$CNT" = "0" ] || [ -z "$CNT" ]; then
        echo "Re-seeding products..."
        /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root < /workspace/config/seed_data.sql 2>/dev/null || true
        break
    fi
done

# Ensure lab analysis codes exist
GLUC_COUNT=$(clinical_query "SELECT COUNT(*) FROM labanalysis WHERE labcode IN ('HBA1C', 'CREAT')" | tr -d '[:space:]')
if [ "$GLUC_COUNT" = "0" ]; then
    /opt/openclinic/mysql5/bin/mysql -S /tmp/mysql5.sock -u root < /workspace/config/seed_data.sql 2>/dev/null || true
fi

# ---------------------------------------------------------------
# Record baseline counts for verifier delta-based checking
# ---------------------------------------------------------------
INITIAL_PATIENT_COUNT=$(admin_query "SELECT COUNT(*) FROM adminview" | tr -d '[:space:]')
INITIAL_HR_COUNT=$(clinical_query "SELECT COUNT(*) FROM healthrecord" | tr -d '[:space:]')
INITIAL_CHRMED_COUNT=$(clinical_query "SELECT COUNT(*) FROM oc_chronicmedications" | tr -d '[:space:]')
INITIAL_LAB_COUNT=$(clinical_query "SELECT COUNT(*) FROM requestedlabanalyses" | tr -d '[:space:]')
INITIAL_PLAN_COUNT=$(clinical_query "SELECT COUNT(*) FROM oc_planning" | tr -d '[:space:]')

echo "$INITIAL_PATIENT_COUNT" > /tmp/complex_intake_baseline_patients
echo "$INITIAL_HR_COUNT"      > /tmp/complex_intake_baseline_hr
echo "$INITIAL_CHRMED_COUNT"  > /tmp/complex_intake_baseline_chrmed
echo "$INITIAL_LAB_COUNT"     > /tmp/complex_intake_baseline_labs
echo "$INITIAL_PLAN_COUNT"    > /tmp/complex_intake_baseline_plan
START_TS=$(date +%s)
echo "$START_TS"              > /tmp/complex_intake_start_ts

echo "Baseline counts:"
echo "  Patients: $INITIAL_PATIENT_COUNT"
echo "  Health records: $INITIAL_HR_COUNT"
echo "  Chronic meds: $INITIAL_CHRMED_COUNT"
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
echo "=== Complex Patient Transfer Intake task ready ==="
echo ""
echo "TASK: Complete full intake for new transfer patient:"
echo "  Name:    Amara Nwosu"
echo "  DOB:     1972-04-19 (April 19, 1972)"
echo "  Gender:  Female"
echo "  Country: NG (Nigeria)"
echo "  Dx:      Type 2 Diabetes Mellitus + Hypertension"
echo ""
echo "Required steps:"
echo "  1. Register patient demographics"
echo "  2. Create clinical encounter"
echo "  3. Add chronic meds: Metformin 500mg + Amlodipine 5mg"
echo "  4. Order labs: HbA1c (HBA1C) + Creatinine (CREAT)"
echo "  5. Schedule follow-up appointment"
echo ""
echo "Login: username=4, password=openclinic"
