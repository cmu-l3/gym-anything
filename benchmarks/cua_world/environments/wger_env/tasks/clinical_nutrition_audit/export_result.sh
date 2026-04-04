#!/bin/bash
# Export results: clinical_nutrition_audit
# Queries the wger database for the corrected energy goals, new measurement
# categories, and the new nutrition plan, then writes the result JSON.

source /workspace/scripts/task_utils.sh

echo "=== Exporting clinical_nutrition_audit results ==="

# Take final screenshot
take_screenshot /tmp/task_clinical_nutrition_audit_final.png

# -----------------------------------------------------------------------
# Read plan IDs and initial state from setup
# -----------------------------------------------------------------------
PLAN_A_ID=0
PLAN_B_ID=0
PLAN_C_ID=0
if [ -f /tmp/clinical_nutrition_plan_ids.json ]; then
    PLAN_A_ID=$(python3 -c "import json; d=json.load(open('/tmp/clinical_nutrition_plan_ids.json')); print(d.get('plan_a_id', 0))" 2>/dev/null || echo "0")
    PLAN_B_ID=$(python3 -c "import json; d=json.load(open('/tmp/clinical_nutrition_plan_ids.json')); print(d.get('plan_b_id', 0))" 2>/dev/null || echo "0")
    PLAN_C_ID=$(python3 -c "import json; d=json.load(open('/tmp/clinical_nutrition_plan_ids.json')); print(d.get('plan_c_id', 0))" 2>/dev/null || echo "0")
fi

INITIAL_MEASUREMENT_COUNT=0
if [ -f /tmp/clinical_nutrition_initial.json ]; then
    INITIAL_MEASUREMENT_COUNT=$(python3 -c "import json; d=json.load(open('/tmp/clinical_nutrition_initial.json')); print(d.get('initial_measurement_count', 0))" 2>/dev/null || echo "0")
fi

# -----------------------------------------------------------------------
# Query current energy goals for the 3 plans
# -----------------------------------------------------------------------
PLAN_A_ENERGY=$(db_query "SELECT goal_energy FROM nutrition_nutritionplan WHERE id = ${PLAN_A_ID}" | tr -d '[:space:]')
PLAN_B_ENERGY=$(db_query "SELECT goal_energy FROM nutrition_nutritionplan WHERE id = ${PLAN_B_ID}" | tr -d '[:space:]')
PLAN_C_ENERGY=$(db_query "SELECT goal_energy FROM nutrition_nutritionplan WHERE id = ${PLAN_C_ID}" | tr -d '[:space:]')

# Handle empty / null values
PLAN_A_ENERGY="${PLAN_A_ENERGY:-0}"
PLAN_B_ENERGY="${PLAN_B_ENERGY:-0}"
PLAN_C_ENERGY="${PLAN_C_ENERGY:-0}"

# -----------------------------------------------------------------------
# Query measurement categories
# -----------------------------------------------------------------------
docker exec wger-web python3 manage.py shell -c "
import json
from wger.measurement.models import Category

categories = {}
for cname, expected_unit in [('Resting Heart Rate', 'bpm'), ('Blood Glucose', 'mg/dL')]:
    qs = Category.objects.filter(name=cname)
    if qs.exists():
        cat = qs.first()
        categories[cname] = {
            'exists': True,
            'unit': cat.unit if hasattr(cat, 'unit') else ''
        }
    else:
        categories[cname] = {'exists': False}

print(json.dumps(categories))
" 2>/dev/null > /tmp/_cna_categories.json || echo '{}' > /tmp/_cna_categories.json

CATEGORIES_JSON=$(cat /tmp/_cna_categories.json 2>/dev/null || echo '{}')

# -----------------------------------------------------------------------
# Query the new nutrition plan (Patient D)
# -----------------------------------------------------------------------
ADMIN_ID=$(db_query "SELECT id FROM auth_user WHERE username='admin'" | tr -d '[:space:]')
PLAN_D_EXISTS="false"
PLAN_D_DATA=$(db_query "SELECT id FROM nutrition_nutritionplan WHERE description='Renal Nutrition Support - Patient D' AND user_id=${ADMIN_ID} LIMIT 1" | tr -d '[:space:]')
if [ -n "$PLAN_D_DATA" ]; then
    PLAN_D_EXISTS="true"
fi

# -----------------------------------------------------------------------
# Assemble result JSON
# -----------------------------------------------------------------------
cat > /tmp/clinical_nutrition_result.json << JSONEOF
{
  "plan_a_id": ${PLAN_A_ID},
  "plan_a_current_energy": ${PLAN_A_ENERGY},
  "plan_b_id": ${PLAN_B_ID},
  "plan_b_current_energy": ${PLAN_B_ENERGY},
  "plan_c_id": ${PLAN_C_ID},
  "plan_c_current_energy": ${PLAN_C_ENERGY},
  "measurement_categories": ${CATEGORIES_JSON},
  "plan_d_exists": ${PLAN_D_EXISTS},
  "initial_measurement_count": ${INITIAL_MEASUREMENT_COUNT}
}
JSONEOF

echo "Results exported to /tmp/clinical_nutrition_result.json"
cat /tmp/clinical_nutrition_result.json

# Clean up temp files
rm -f /tmp/_cna_categories.json

echo "=== Export complete: clinical_nutrition_audit ==="
