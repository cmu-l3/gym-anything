#!/bin/bash
# Export results: athlete_body_composition_program
# Queries the wger database for all entities the agent should have created:
# weight entries, measurement categories, routine with days and exercises,
# and nutrition plan with macronutrient goals.

source /workspace/scripts/task_utils.sh

echo "=== Exporting athlete_body_composition_program results ==="

# Take final screenshot
take_screenshot /tmp/task_athlete_body_comp_final.png

# -----------------------------------------------------------------------
# Query everything via Django shell for reliable results
# -----------------------------------------------------------------------
docker exec wger-web python3 manage.py shell -c "
import json
from django.contrib.auth.models import User
from wger.weight.models import WeightEntry
from wger.manager.models import Routine, Day, Setting
from wger.exercises.models import Exercise
from wger.measurement.models import Category as MeasureCategory
from wger.nutrition.models import NutritionPlan

admin = User.objects.get(username='admin')
result = {}

# --- Weight entries ---
target_dates = ['2026-02-03', '2026-02-10', '2026-02-17', '2026-02-24', '2026-03-03']
expected_weights = [79.4, 78.9, 78.2, 77.8, 77.1]
weight_entries = {}
for d, expected_w in zip(target_dates, expected_weights):
    qs = WeightEntry.objects.filter(user=admin, date=d)
    if qs.exists():
        entry = qs.first()
        weight_entries[d] = {
            'exists': True,
            'weight_kg': float(entry.weight),
            'expected_kg': expected_w
        }
    else:
        weight_entries[d] = {
            'exists': False,
            'expected_kg': expected_w
        }
result['weight_entries'] = weight_entries

# --- Measurement categories ---
categories = {}
for cname, expected_unit in [('Skinfold Sum', 'mm'), ('Grip Strength', 'kg')]:
    qs = MeasureCategory.objects.filter(name=cname, user=admin)
    if qs.exists():
        cat = qs.first()
        categories[cname] = {
            'exists': True,
            'unit': cat.unit if hasattr(cat, 'unit') else ''
        }
    else:
        categories[cname] = {'exists': False}
result['measurement_categories'] = categories

# --- Routine ---
routine_qs = Routine.objects.filter(name='Off-Season Wrestling Strength', user=admin)
routine_data = {'found': False}
if routine_qs.exists():
    routine = routine_qs.first()
    routine_data['found'] = True
    routine_data['description'] = routine.description or ''
    days_data = []
    for day in Day.objects.filter(routine=routine).order_by('id'):
        day_info = {
            'name': day.name,
            'day_of_week': list(day.day.values_list('id', flat=True))
        }
        # Get exercises assigned to this day via slots
        exercises_in_day = []
        try:
            for slot in day.slot_set.all():
                for setting in slot.setting_set.all():
                    ex = setting.exercise
                    exercises_in_day.append({
                        'id': ex.id,
                        'name': ex.name if hasattr(ex, 'name') else str(ex)
                    })
        except Exception:
            pass
        day_info['exercises'] = exercises_in_day
        days_data.append(day_info)
    routine_data['days'] = days_data
result['routine'] = routine_data

# --- Nutrition plan ---
plan_qs = NutritionPlan.objects.filter(description='Wrestling Weight Management - Off-Season', user=admin)
plan_data = {'found': False}
if plan_qs.exists():
    plan = plan_qs.first()
    plan_data['found'] = True
    plan_data['goal_energy'] = float(plan.goal_energy) if plan.goal_energy else 0
    plan_data['goal_protein'] = float(plan.goal_protein) if plan.goal_protein else 0
    plan_data['goal_carbohydrates'] = float(plan.goal_carbohydrates) if plan.goal_carbohydrates else 0
    plan_data['goal_fat'] = float(plan.goal_fat) if plan.goal_fat else 0
result['nutrition_plan'] = plan_data

# --- Baselines ---
try:
    with open('/tmp/athlete_body_comp_initial.json') as f:
        result['baselines'] = json.load(f)
except Exception:
    result['baselines'] = {}

print(json.dumps(result))
" 2>/dev/null > /tmp/athlete_body_comp_result.json

if [ -f /tmp/athlete_body_comp_result.json ]; then
    echo "Results exported to /tmp/athlete_body_comp_result.json"
    cat /tmp/athlete_body_comp_result.json
else
    echo "Warning: Failed to export results"
    echo '{}' > /tmp/athlete_body_comp_result.json
fi

echo "=== Export complete: athlete_body_composition_program ==="
