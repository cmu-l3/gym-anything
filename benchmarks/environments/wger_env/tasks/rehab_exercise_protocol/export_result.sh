#!/bin/bash
# Task export: rehab_exercise_protocol
# Queries all task-relevant state from the wger database and writes
# a structured JSON to /tmp/rehab_protocol_result.json

source /workspace/scripts/task_utils.sh

echo "=== Exporting rehab_exercise_protocol result ==="

take_screenshot /tmp/rehab_protocol_end.png

docker exec wger-web python3 manage.py shell -c "
import json
from django.contrib.auth.models import User
from wger.weight.models import WeightEntry
from wger.manager.models import Routine, Day, Slot, SlotEntry
from wger.measurement.models import Category as MeasureCategory, Entry as MeasureEntry
from wger.nutrition.models import NutritionPlan

admin = User.objects.get(username='admin')

# ---- Weight entries ----
target_dates = ['2026-01-12','2026-01-19','2026-01-26',
                '2026-02-02','2026-02-09','2026-02-16']
weight_entries = {}
for d in target_dates:
    qs = WeightEntry.objects.filter(user=admin, date=d)
    if qs.exists():
        weight_entries[d] = {'exists': True, 'weight_kg': float(qs.first().weight)}
    else:
        weight_entries[d] = {'exists': False, 'weight_kg': None}

# ---- Measurement categories and entries ----
category_names = ['6-Minute Walk Distance', 'Resting Systolic BP', 'Borg RPE Score']
measurement_data = {}
for cat_name in category_names:
    qs_cat = MeasureCategory.objects.filter(user=admin, name=cat_name)
    if qs_cat.exists():
        cat = qs_cat.first()
        entries_qs = MeasureEntry.objects.filter(category=cat).order_by('date')
        entries = {}
        for e in entries_qs:
            entries[str(e.date)] = float(e.value)
        measurement_data[cat_name] = {
            'exists': True,
            'unit': cat.unit,
            'entries': entries
        }
    else:
        measurement_data[cat_name] = {'exists': False, 'unit': None, 'entries': {}}

# ---- Routine ----
routine_qs = Routine.objects.filter(user=admin, name='Phase II Cardiac Rehabilitation Protocol')
routine_data = {'found': False, 'description': None, 'days': []}
if routine_qs.exists():
    routine = routine_qs.first()
    routine_data['found'] = True
    routine_data['description'] = routine.description or ''
    for day in Day.objects.filter(routine=routine).order_by('order'):
        day_info = {
            'name': day.name,
            'day_of_week': list(day.day.values_list('day_of_week', flat=True)),
            'exercises': []
        }
        for slot in Slot.objects.filter(day=day):
            for se in SlotEntry.objects.filter(slot=slot):
                try:
                    ex_name = se.exercise.get_base().translations.filter(language=2).first()
                    if ex_name:
                        day_info['exercises'].append(ex_name.name)
                    else:
                        day_info['exercises'].append(str(se.exercise_id))
                except Exception:
                    day_info['exercises'].append(str(se.exercise_id))
        routine_data['days'].append(day_info)

# ---- Nutrition plan ----
plan_qs = NutritionPlan.objects.filter(user=admin, description='Cardiac Heart-Healthy Eating Plan')
plan_data = {'found': False}
if plan_qs.exists():
    plan = plan_qs.first()
    plan_data = {
        'found': True,
        'goal_energy': float(plan.goal_energy) if plan.goal_energy else 0,
        'goal_protein': float(plan.goal_protein) if plan.goal_protein else 0,
        'goal_carbohydrates': float(plan.goal_carbohydrates) if plan.goal_carbohydrates else 0,
        'goal_fat': float(plan.goal_fat) if plan.goal_fat else 0,
    }

result = {
    'weight_entries': weight_entries,
    'measurement_data': measurement_data,
    'routine': routine_data,
    'nutrition_plan': plan_data,
}
print(json.dumps(result, indent=2))
" 2>/dev/null > /tmp/rehab_protocol_result.json || echo '{}' > /tmp/rehab_protocol_result.json

echo "Result written to /tmp/rehab_protocol_result.json"
cat /tmp/rehab_protocol_result.json

echo "=== Export complete: rehab_exercise_protocol ==="
