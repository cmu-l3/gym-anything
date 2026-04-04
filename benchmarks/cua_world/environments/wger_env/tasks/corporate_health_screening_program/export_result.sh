#!/bin/bash
# Task export: corporate_health_screening_program
# Queries all task-relevant state from the wger database and writes
# a structured JSON to /tmp/corp_health_result.json

source /workspace/scripts/task_utils.sh

echo "=== Exporting corporate_health_screening_program result ==="

take_screenshot /tmp/corp_health_end.png

docker exec wger-web python3 manage.py shell -c "
import json
from django.contrib.auth.models import User
from wger.manager.models import Routine, Day, Slot, SlotEntry
from wger.measurement.models import Category as MeasureCategory
from wger.nutrition.models import NutritionPlan, Meal
from wger.gym.models import GymUserConfig

admin = User.objects.get(username='admin')

# ---- User registration check ----
expected_users = [
    {'username': 'dwilliams_meridian', 'email': 'd.williams@meridian-ind.com'},
    {'username': 'rparker_meridian', 'email': 'r.parker@meridian-ind.com'},
    {'username': 'lchavez_meridian', 'email': 'l.chavez@meridian-ind.com'},
]
users_data = []
for eu in expected_users:
    qs = User.objects.filter(username=eu['username'])
    if qs.exists():
        u = qs.first()
        email_match = u.email.lower() == eu['email'].lower()
        users_data.append({
            'username': eu['username'],
            'exists': True,
            'email_correct': email_match,
            'email_found': u.email,
        })
    else:
        users_data.append({
            'username': eu['username'],
            'exists': False,
            'email_correct': False,
            'email_found': None,
        })

# ---- Routine ----
routine_qs = Routine.objects.filter(user=admin, name='Meridian Ergonomic Wellness Circuit')
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
plan_qs = NutritionPlan.objects.filter(user=admin, description='Meridian Metabolic Risk Reduction Plan')
plan_data = {'found': False}
if plan_qs.exists():
    plan = plan_qs.first()
    meals = list(Meal.objects.filter(plan=plan).values_list('name', flat=True))
    plan_data = {
        'found': True,
        'goal_energy': float(plan.goal_energy) if plan.goal_energy else 0,
        'goal_protein': float(plan.goal_protein) if plan.goal_protein else 0,
        'goal_carbohydrates': float(plan.goal_carbohydrates) if plan.goal_carbohydrates else 0,
        'goal_fat': float(plan.goal_fat) if plan.goal_fat else 0,
        'meal_names': meals,
        'meal_count': len(meals),
    }

# ---- Measurement categories ----
category_names = ['Waist Circumference', 'Resting Heart Rate']
measurement_data = {}
for cat_name in category_names:
    qs_cat = MeasureCategory.objects.filter(user=admin, name=cat_name)
    if qs_cat.exists():
        cat = qs_cat.first()
        measurement_data[cat_name] = {'exists': True, 'unit': cat.unit}
    else:
        measurement_data[cat_name] = {'exists': False, 'unit': None}

result = {
    'users': users_data,
    'routine': routine_data,
    'nutrition_plan': plan_data,
    'measurement_categories': measurement_data,
}
print(json.dumps(result, indent=2))
" 2>/dev/null > /tmp/corp_health_result.json || echo '{}' > /tmp/corp_health_result.json

echo "Result written to /tmp/corp_health_result.json"
cat /tmp/corp_health_result.json

echo "=== Export complete: corporate_health_screening_program ==="
