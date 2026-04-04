#!/bin/bash
# Task export: sports_nutrition_consultation
# Queries all task-relevant state from the wger database and writes
# a structured JSON to /tmp/sports_nutrition_result.json

source /workspace/scripts/task_utils.sh

echo "=== Exporting sports_nutrition_consultation result ==="

take_screenshot /tmp/sports_nutrition_end.png

docker exec wger-web python3 manage.py shell -c "
import json
from django.contrib.auth.models import User
from wger.weight.models import WeightEntry
from wger.measurement.models import Category as MeasureCategory, Entry as MeasureEntry
from wger.nutrition.models import NutritionPlan, Meal

admin = User.objects.get(username='admin')

# ---- Weight entries ----
target_dates = ['2026-01-05','2026-01-12','2026-01-19','2026-01-26',
                '2026-02-02','2026-02-09','2026-02-16','2026-02-23']
weight_entries = {}
for d in target_dates:
    qs = WeightEntry.objects.filter(user=admin, date=d)
    if qs.exists():
        weight_entries[d] = {'exists': True, 'weight_kg': float(qs.first().weight)}
    else:
        weight_entries[d] = {'exists': False, 'weight_kg': None}

# ---- Measurement categories and entries ----
category_names = ['Body Fat Percentage', 'Lean Body Mass', 'Vertical Jump Height']
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

# ---- Nutrition plans ----
def get_plan_data(description):
    qs = NutritionPlan.objects.filter(user=admin, description=description)
    if not qs.exists():
        return {'found': False}
    plan = qs.first()
    meals = list(Meal.objects.filter(plan=plan).values_list('name', flat=True))
    return {
        'found': True,
        'goal_energy': float(plan.goal_energy) if plan.goal_energy else 0,
        'goal_protein': float(plan.goal_protein) if plan.goal_protein else 0,
        'goal_carbohydrates': float(plan.goal_carbohydrates) if plan.goal_carbohydrates else 0,
        'goal_fat': float(plan.goal_fat) if plan.goal_fat else 0,
        'meal_names': meals,
        'meal_count': len(meals),
    }

offseason_plan = get_plan_data('Powerlifter Off-Season Hypertrophy Phase')
competition_plan = get_plan_data('Powerlifter Competition Peak - Weight Cut')

result = {
    'weight_entries': weight_entries,
    'measurement_data': measurement_data,
    'offseason_plan': offseason_plan,
    'competition_plan': competition_plan,
}
print(json.dumps(result, indent=2))
" 2>/dev/null > /tmp/sports_nutrition_result.json || echo '{}' > /tmp/sports_nutrition_result.json

echo "Result written to /tmp/sports_nutrition_result.json"
cat /tmp/sports_nutrition_result.json

echo "=== Export complete: sports_nutrition_consultation ==="
