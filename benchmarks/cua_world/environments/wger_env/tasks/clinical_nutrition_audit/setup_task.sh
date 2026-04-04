#!/bin/bash
# Task setup: clinical_nutrition_audit
# Creates 3 nutrition plans with WRONG energy goals, writes an audit report
# with the correct values, and navigates to the nutrition overview.

source /workspace/scripts/task_utils.sh

# Lesson 120: ensure export script is executable
chmod +x /workspace/tasks/clinical_nutrition_audit/export_result.sh

echo "=== Setting up clinical_nutrition_audit task ==="

# Ensure wger is responding
wait_for_wger_page

TOKEN=$(get_wger_token)
if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to get wger API token"
    exit 1
fi

# ---------------------------------------------------------------------------
# Clean up any pre-existing plans with matching descriptions
# ---------------------------------------------------------------------------
for DESC in "Cardiac Rehab - Patient A" "Diabetes Management - Patient B" "Post-Bariatric - Patient C" "Renal Nutrition Support - Patient D"; do
    docker exec wger-web python3 manage.py shell -c "
from wger.nutrition.models import NutritionPlan
deleted = NutritionPlan.objects.filter(description='${DESC}', user__username='admin').delete()
print(f'Deleted {DESC}: {deleted}')
" 2>/dev/null || true
done

# ---------------------------------------------------------------------------
# Clean up any pre-existing measurement categories named
# "Resting Heart Rate" or "Blood Glucose"
# ---------------------------------------------------------------------------
docker exec wger-web python3 manage.py shell -c "
from wger.measurement.models import Category
for name in ['Resting Heart Rate', 'Blood Glucose']:
    deleted = Category.objects.filter(name=name).delete()
    print(f'Deleted measurement category {name}: {deleted}')
" 2>/dev/null || true

sleep 1

# ---------------------------------------------------------------------------
# Create 3 nutrition plans with WRONG energy goals
# ---------------------------------------------------------------------------
PLAN_A_RESPONSE=$(curl -s -L -X POST "http://localhost/api/v2/nutritionplan/" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d '{"description": "Cardiac Rehab - Patient A"}' \
    2>/dev/null)

PLAN_A_ID=$(echo "$PLAN_A_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
if [ -z "$PLAN_A_ID" ]; then
    echo "ERROR: Failed to create Cardiac Rehab plan"
    echo "Response: $PLAN_A_RESPONSE"
    exit 1
fi
echo "Created Cardiac Rehab - Patient A with ID: $PLAN_A_ID"

# Set WRONG energy goal: 2800 (should be 1800)
curl -s -L -X PATCH "http://localhost/api/v2/nutritionplan/${PLAN_A_ID}/" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d '{"goal_energy": 2800}' 2>/dev/null > /dev/null

sleep 0.5

PLAN_B_RESPONSE=$(curl -s -L -X POST "http://localhost/api/v2/nutritionplan/" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d '{"description": "Diabetes Management - Patient B"}' \
    2>/dev/null)

PLAN_B_ID=$(echo "$PLAN_B_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
if [ -z "$PLAN_B_ID" ]; then
    echo "ERROR: Failed to create Diabetes Management plan"
    echo "Response: $PLAN_B_RESPONSE"
    exit 1
fi
echo "Created Diabetes Management - Patient B with ID: $PLAN_B_ID"

# Set WRONG energy goal: 3200 (should be 2100)
curl -s -L -X PATCH "http://localhost/api/v2/nutritionplan/${PLAN_B_ID}/" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d '{"goal_energy": 3200}' 2>/dev/null > /dev/null

sleep 0.5

PLAN_C_RESPONSE=$(curl -s -L -X POST "http://localhost/api/v2/nutritionplan/" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d '{"description": "Post-Bariatric - Patient C"}' \
    2>/dev/null)

PLAN_C_ID=$(echo "$PLAN_C_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
if [ -z "$PLAN_C_ID" ]; then
    echo "ERROR: Failed to create Post-Bariatric plan"
    echo "Response: $PLAN_C_RESPONSE"
    exit 1
fi
echo "Created Post-Bariatric - Patient C with ID: $PLAN_C_ID"

# Set WRONG energy goal: 2500 (should be 1400)
curl -s -L -X PATCH "http://localhost/api/v2/nutritionplan/${PLAN_C_ID}/" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d '{"goal_energy": 2500}' 2>/dev/null > /dev/null

sleep 0.5

# ---------------------------------------------------------------------------
# Save plan IDs to JSON for use by export_result.sh
# ---------------------------------------------------------------------------
cat > /tmp/clinical_nutrition_plan_ids.json << EOF
{
    "plan_a_id": ${PLAN_A_ID},
    "plan_b_id": ${PLAN_B_ID},
    "plan_c_id": ${PLAN_C_ID}
}
EOF

echo "Plan IDs saved to /tmp/clinical_nutrition_plan_ids.json"

# ---------------------------------------------------------------------------
# Write the clinical audit report
# ---------------------------------------------------------------------------
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/nutrition_audit_report.txt << 'AUDIT_EOF'
QUARTERLY CLINICAL NUTRITION AUDIT REPORT
Facility: Regional Medical Center — Outpatient Nutrition Services
Audit Date: 2026-03-07
Auditor: Licensed RD Staff
==========================================================

FINDING 1 — CALORIC GOAL ERRORS
The following nutrition plans have incorrect daily energy targets.
Correct each plan's energy goal (kcal) to the clinically recommended value:

Plan: "Cardiac Rehab - Patient A"
Current (incorrect) energy goal: 2800 kcal
Corrected energy goal: 1800 kcal
Rationale: AHA guidelines for post-MI cardiac rehabilitation

Plan: "Diabetes Management - Patient B"
Current (incorrect) energy goal: 3200 kcal
Corrected energy goal: 2100 kcal
Rationale: ADA medical nutrition therapy for Type 2 DM with BMI >30

Plan: "Post-Bariatric - Patient C"
Current (incorrect) energy goal: 2500 kcal
Corrected energy goal: 1400 kcal
Rationale: ASMBS post-Roux-en-Y month 4-6 caloric progression protocol

FINDING 2 — MISSING MEASUREMENT CATEGORIES
Create the following clinical tracking categories:

Category: "Resting Heart Rate"
Unit: bpm

Category: "Blood Glucose"
Unit: mg/dL

FINDING 3 — NEW PATIENT PLAN REQUIRED
Create a new nutrition plan:
Description: "Renal Nutrition Support - Patient D"
(Energy goal will be set during the next clinical review; leave goal unset for now)

END OF AUDIT REPORT
AUDIT_EOF

chown ga:ga /home/ga/Documents/nutrition_audit_report.txt 2>/dev/null || true
echo "Audit report written to /home/ga/Documents/nutrition_audit_report.txt"

# ---------------------------------------------------------------------------
# Record initial state for verification baseline
# ---------------------------------------------------------------------------
PLAN_A_ENERGY=$(db_query "SELECT goal_energy FROM nutrition_nutritionplan WHERE id = ${PLAN_A_ID}")
PLAN_B_ENERGY=$(db_query "SELECT goal_energy FROM nutrition_nutritionplan WHERE id = ${PLAN_B_ID}")
PLAN_C_ENERGY=$(db_query "SELECT goal_energy FROM nutrition_nutritionplan WHERE id = ${PLAN_C_ID}")
MEASUREMENT_COUNT=$(db_query "SELECT COUNT(*) FROM measurement_category")

cat > /tmp/clinical_nutrition_initial.json << EOF
{
    "plan_a_id": ${PLAN_A_ID},
    "plan_a_initial_energy": ${PLAN_A_ENERGY:-0},
    "plan_b_id": ${PLAN_B_ID},
    "plan_b_initial_energy": ${PLAN_B_ENERGY:-0},
    "plan_c_id": ${PLAN_C_ID},
    "plan_c_initial_energy": ${PLAN_C_ENERGY:-0},
    "initial_measurement_count": ${MEASUREMENT_COUNT:-0}
}
EOF

echo "Initial state saved to /tmp/clinical_nutrition_initial.json"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp recorded"

# ---------------------------------------------------------------------------
# Launch Firefox to the nutrition overview
# ---------------------------------------------------------------------------
launch_firefox_to "http://localhost/en/nutrition/overview/" 5

# Take starting screenshot
take_screenshot /tmp/task_clinical_nutrition_audit_start.png

echo "=== Task setup complete: clinical_nutrition_audit ==="
echo "Plan A (Cardiac Rehab): ID=${PLAN_A_ID}, goal_energy=2800 (wrong)"
echo "Plan B (Diabetes Mgmt): ID=${PLAN_B_ID}, goal_energy=3200 (wrong)"
echo "Plan C (Post-Bariatric): ID=${PLAN_C_ID}, goal_energy=2500 (wrong)"
