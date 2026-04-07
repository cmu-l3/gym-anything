#!/bin/bash
set -e
echo "=== Setting up add_relationship task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure data is seeded if needed
# We need at least 2 patients. Check count.
PATIENT_COUNT=$(omrs_db_query "SELECT COUNT(*) FROM patient WHERE voided=0" 2>/dev/null || echo "0")
if [ "$PATIENT_COUNT" -lt 2 ]; then
    echo "Insufficient patients found ($PATIENT_COUNT). Seeding data..."
    bash /workspace/scripts/seed_data.sh
    sleep 5
fi

# 3. Select two distinct patients
echo "Selecting two patients..."
# Get first patient
PATIENT_A_ROW=$(omrs_db_query "
    SELECT p.uuid, pn.given_name, pn.family_name, p.person_id
    FROM patient pat
    JOIN person p ON pat.patient_id = p.person_id
    JOIN person_name pn ON p.person_id = pn.person_id
    WHERE pn.preferred = 1 AND p.voided = 0 AND pat.voided = 0
    ORDER BY pat.patient_id ASC LIMIT 1
")

# Get second patient
PATIENT_B_ROW=$(omrs_db_query "
    SELECT p.uuid, pn.given_name, pn.family_name, p.person_id
    FROM patient pat
    JOIN person p ON pat.patient_id = p.person_id
    JOIN person_name pn ON p.person_id = pn.person_id
    WHERE pn.preferred = 1 AND p.voided = 0 AND pat.voided = 0
    ORDER BY pat.patient_id ASC LIMIT 1 OFFSET 1
")

# Parse Patient A
PA_UUID=$(echo "$PATIENT_A_ROW" | awk '{print $1}')
PA_GIVEN=$(echo "$PATIENT_A_ROW" | awk '{print $2}')
PA_FAMILY=$(echo "$PATIENT_A_ROW" | awk '{print $3}')
PA_ID=$(echo "$PATIENT_A_ROW" | awk '{print $4}')

# Parse Patient B
PB_UUID=$(echo "$PATIENT_B_ROW" | awk '{print $1}')
PB_GIVEN=$(echo "$PATIENT_B_ROW" | awk '{print $2}')
PB_FAMILY=$(echo "$PATIENT_B_ROW" | awk '{print $3}')
PB_ID=$(echo "$PATIENT_B_ROW" | awk '{print $4}')

echo "Selected Patient A: $PA_GIVEN $PA_FAMILY ($PA_UUID)"
echo "Selected Patient B: $PB_GIVEN $PB_FAMILY ($PB_UUID)"

# 4. Remove any existing relationship between them
echo "Cleaning existing relationships..."
if [ -n "$PA_ID" ] && [ -n "$PB_ID" ]; then
    omrs_db_query "DELETE FROM relationship WHERE (person_a = $PA_ID AND person_b = $PB_ID) OR (person_a = $PB_ID AND person_b = $PA_ID)"
fi

# 5. Write parameters for the agent
cat > /tmp/task_params.txt << EOF
Patient A (Current Chart): $PA_GIVEN $PA_FAMILY
Patient B (Sibling to add): $PB_GIVEN $PB_FAMILY
EOF

# 6. Save internal state for verification
cat > /tmp/task_internal_state.json << EOF
{
    "patient_a_uuid": "$PA_UUID",
    "patient_b_uuid": "$PB_UUID",
    "person_a_id": "$PA_ID",
    "person_b_id": "$PB_ID",
    "patient_b_name": "$PB_GIVEN $PB_FAMILY"
}
EOF

# 7. Record initial relationship count
INITIAL_REL_COUNT=$(omrs_db_query "SELECT COUNT(*) FROM relationship WHERE voided=0" 2>/dev/null || echo "0")
echo "$INITIAL_REL_COUNT" > /tmp/initial_rel_count.txt

# 8. Open Firefox to Patient A's chart
CHART_URL="http://localhost/openmrs/spa/patient/${PA_UUID}/chart"
ensure_openmrs_logged_in "$CHART_URL"

# 9. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="