#!/bin/bash
# Export result: corporate_wellness_challenge
# Queries the wger database for all entities the agent was supposed to create,
# then writes a structured JSON result file for the verifier to consume.

source /workspace/scripts/task_utils.sh

echo "=== Exporting corporate_wellness_challenge results ==="

# -----------------------------------------------------------------------
# Query the database for all expected entities
# -----------------------------------------------------------------------
docker exec wger-web python3 manage.py shell -c "
import json

from django.contrib.auth.models import User
from wger.manager.models import Routine
from wger.measure.models import Category as MeasureCategory
from wger.nutrition.models import NutritionPlan

result = {}

# --- Check users ---
users_data = {}
for uname, expected_first, expected_last, expected_email in [
    ('maria_chen', 'Maria', 'Chen', 'maria.chen@apexmfg.com'),
    ('david_okonkwo', 'David', 'Okonkwo', 'david.okonkwo@apexmfg.com'),
    ('sarah_patel', 'Sarah', 'Patel', 'sarah.patel@apexmfg.com'),
]:
    try:
        u = User.objects.get(username=uname)
        users_data[uname] = {
            'exists': True,
            'first_name': u.first_name,
            'last_name': u.last_name,
            'email': u.email,
            'expected_first': expected_first,
            'expected_last': expected_last,
            'expected_email': expected_email
        }
    except User.DoesNotExist:
        users_data[uname] = {
            'exists': False,
            'expected_first': expected_first,
            'expected_last': expected_last,
            'expected_email': expected_email
        }

result['users'] = users_data

# --- Check routines ---
routines_data = {}
for rname in ['Cardio Kickstart - Maria', 'Strength Foundations - David', 'Flexibility & Recovery - Sarah']:
    qs = Routine.objects.filter(name=rname)
    routines_data[rname] = {
        'exists': qs.exists(),
        'count': qs.count()
    }
    if qs.exists():
        r = qs.first()
        routines_data[rname]['description'] = r.description if hasattr(r, 'description') else ''

result['routines'] = routines_data

# --- Check measurement categories ---
bmi_qs = MeasureCategory.objects.filter(name='BMI')
bmi_data = {
    'exists': bmi_qs.exists(),
    'count': bmi_qs.count()
}
if bmi_qs.exists():
    cat = bmi_qs.first()
    bmi_data['unit'] = cat.unit if hasattr(cat, 'unit') else ''

result['measurement_category_bmi'] = bmi_data

# --- Check nutrition plan ---
plan_qs = NutritionPlan.objects.filter(description='Apex Wellness Q1 Team Plan')
plan_data = {
    'exists': plan_qs.exists(),
    'count': plan_qs.count()
}

result['nutrition_plan'] = plan_data

# --- Read baselines ---
try:
    with open('/tmp/corporate_wellness_initial.json') as f:
        result['baselines'] = json.load(f)
except Exception:
    result['baselines'] = {}

print(json.dumps(result))
" 2>/dev/null > /tmp/corporate_wellness_result.json

if [ -f /tmp/corporate_wellness_result.json ]; then
    echo "Results exported to /tmp/corporate_wellness_result.json"
    cat /tmp/corporate_wellness_result.json
else
    echo "Warning: Failed to export results, writing empty result"
    echo '{"users":{},"routines":{},"measurement_category_bmi":{"exists":false},"nutrition_plan":{"exists":false},"baselines":{}}' > /tmp/corporate_wellness_result.json
fi

echo "=== Export complete: corporate_wellness_challenge ==="
