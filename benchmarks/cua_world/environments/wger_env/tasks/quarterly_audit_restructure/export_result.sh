#!/bin/bash
# Task export: quarterly_audit_restructure
# Queries the wger database for the full post-task state and writes
# a comprehensive JSON to /tmp/task_result.json for verification.

source /workspace/scripts/task_utils.sh

echo "=== Exporting quarterly_audit_restructure result ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ---------------------------------------------------------------------------
# Extract all task-relevant state from the database
# ---------------------------------------------------------------------------
cat > /tmp/export_audit.py << 'PYEOF'
import json, datetime, traceback

from django.contrib.auth.models import User
from wger.weight.models import WeightEntry
from wger.manager.models import Routine, Day, Slot, SlotEntry, SetsConfig, RepetitionsConfig
from wger.exercises.models import Exercise, Translation
from wger.nutrition.models import NutritionPlan, Meal, MealItem
from wger.measurements.models import Category as MeasureCategory, Measurement as MeasureEntry
from wger.core.models import Language

try:
    admin = User.objects.get(username='admin')

    # Load baselines recorded during setup
    try:
        with open('/tmp/quarterly_audit_baselines.json') as f:
            baselines = json.load(f)
    except Exception:
        baselines = {}

    # ---- Weight entries (all 12 target dates) ----
    target_dates = [
        '2025-12-29', '2026-01-05', '2026-01-12', '2026-01-19',
        '2026-01-26', '2026-02-02', '2026-02-09', '2026-02-16',
        '2026-02-23', '2026-03-02', '2026-03-09', '2026-03-16',
    ]
    weight_entries = {}
    for d in target_dates:
        qs = WeightEntry.objects.filter(user=admin, date=d)
        if qs.exists():
            weight_entries[d] = float(qs.first().weight)
        else:
            weight_entries[d] = None
    total_weight_count = WeightEntry.objects.filter(user=admin).count()

    # ---- Measurement categories and entries ----
    measurement_data = {}
    for cat_name in ['Body Fat Percentage', 'Chest Circumference', 'Waist Circumference']:
        qs_cat = MeasureCategory.objects.filter(user=admin, name=cat_name)
        if qs_cat.exists():
            cat = qs_cat.first()
            entries = []
            for e in MeasureEntry.objects.filter(category=cat).order_by('date'):
                entries.append({'date': str(e.date), 'value': float(e.value)})
            measurement_data[cat_name] = {
                'exists': True,
                'unit': cat.unit,
                'entry_count': len(entries),
                'entries': entries,
            }
        else:
            measurement_data[cat_name] = {'exists': False, 'unit': None, 'entry_count': 0, 'entries': []}

    # ---- Routine (check both original and renamed names) ----
    routine_data = {
        'original_name_found': False,
        'new_name_found': False,
        'found_routine': None,
    }

    # Check if original name still exists
    orig_qs = Routine.objects.filter(user=admin, name='Hypertrophy Block A')
    routine_data['original_name_found'] = orig_qs.exists()

    # Check if renamed version exists
    new_qs = Routine.objects.filter(user=admin, name__icontains='Strength-Power Phase B')
    routine_data['new_name_found'] = new_qs.exists()

    # Pick whichever routine to inspect (prefer renamed, fallback to original)
    target_routine = None
    if new_qs.exists():
        target_routine = new_qs.first()
    elif orig_qs.exists():
        target_routine = orig_qs.first()
    else:
        # Fallback: find by original ID from baselines
        orig_id = baselines.get('routine_id')
        if orig_id:
            try:
                target_routine = Routine.objects.get(id=orig_id)
            except Routine.DoesNotExist:
                pass

    en = Language.objects.get(short_name='en')

    if target_routine:
        days_data = []
        for day in Day.objects.filter(routine=target_routine).order_by('order', 'id'):
            day_info = {
                'name': day.name,
                'day_of_week': day.type if day.type else '',
                'exercises': [],
            }

            # Get exercises via Slot -> SlotEntry -> Exercise -> Translation
            for slot in Slot.objects.filter(day=day).order_by('order', 'id'):
                for se in SlotEntry.objects.filter(slot=slot).order_by('order', 'id'):
                    ex_name = ''
                    if se.exercise:
                        t = Translation.objects.filter(exercise=se.exercise, language=en).first()
                        if t:
                            ex_name = t.name
                        else:
                            t = Translation.objects.filter(exercise=se.exercise).first()
                            ex_name = t.name if t else str(se.exercise_id)
                    # Get sets and reps from config models
                    sets_cfg = SetsConfig.objects.filter(slot_entry=se).first()
                    reps_cfg = RepetitionsConfig.objects.filter(slot_entry=se).first()
                    set_count = int(sets_cfg.value) if sets_cfg and sets_cfg.value else 0
                    rep_count = int(reps_cfg.value) if reps_cfg and reps_cfg.value else 0
                    day_info['exercises'].append({
                        'name': ex_name,
                        'sets': set_count,
                        'reps': rep_count,
                    })
            days_data.append(day_info)

        routine_data['found_routine'] = {
            'id': target_routine.id,
            'name': target_routine.name,
            'description': target_routine.description or '',
            'day_count': len(days_data),
            'days': days_data,
        }

    # ---- Nutrition plans ----
    nutrition_data = {
        'maintenance': {'found': False},
        'competition': {'found': False},
    }

    # Maintenance Phase plan
    maint_qs = NutritionPlan.objects.filter(user=admin, description='Maintenance Phase')
    if not maint_qs.exists():
        # Try finding by original ID from baselines
        orig_plan_id = baselines.get('plan_id')
        if orig_plan_id:
            try:
                maint_plan = NutritionPlan.objects.get(id=orig_plan_id)
                maint_qs = NutritionPlan.objects.filter(id=orig_plan_id)
            except NutritionPlan.DoesNotExist:
                pass

    if maint_qs.exists():
        maint_plan = maint_qs.first()
        meals_list = []
        for meal in Meal.objects.filter(plan=maint_plan).order_by('id'):
            items = []
            for item in MealItem.objects.filter(meal=meal):
                items.append({
                    'ingredient': item.ingredient.name if item.ingredient else '',
                    'amount': float(item.amount),
                })
            meals_list.append({
                'name': meal.name or '',
                'item_count': len(items),
                'items': items,
            })
        nutrition_data['maintenance'] = {
            'found': True,
            'id': maint_plan.id,
            'description': maint_plan.description or '',
            'goal_energy': float(maint_plan.goal_energy) if maint_plan.goal_energy else 0,
            'goal_protein': float(maint_plan.goal_protein) if maint_plan.goal_protein else 0,
            'goal_carbohydrates': float(maint_plan.goal_carbohydrates) if maint_plan.goal_carbohydrates else 0,
            'goal_fat': float(maint_plan.goal_fat) if maint_plan.goal_fat else 0,
            'meal_count': len(meals_list),
            'meals': meals_list,
            'meal_names': [m['name'] for m in meals_list],
        }

    # Competition Peak Nutrition plan
    comp_qs = NutritionPlan.objects.filter(user=admin, description='Competition Peak Nutrition')
    if comp_qs.exists():
        comp_plan = comp_qs.first()
        comp_meals = []
        for meal in Meal.objects.filter(plan=comp_plan).order_by('id'):
            comp_meals.append({'name': meal.name or ''})
        nutrition_data['competition'] = {
            'found': True,
            'id': comp_plan.id,
            'goal_energy': float(comp_plan.goal_energy) if comp_plan.goal_energy else 0,
            'goal_protein': float(comp_plan.goal_protein) if comp_plan.goal_protein else 0,
            'goal_carbohydrates': float(comp_plan.goal_carbohydrates) if comp_plan.goal_carbohydrates else 0,
            'goal_fat': float(comp_plan.goal_fat) if comp_plan.goal_fat else 0,
            'meal_count': len(comp_meals),
            'meal_names': [m['name'] for m in comp_meals],
        }

    # ---- Assemble final result ----
    result = {
        'baselines': baselines,
        'weight_entries': weight_entries,
        'total_weight_count': total_weight_count,
        'measurement_data': measurement_data,
        'routine': routine_data,
        'nutrition': nutrition_data,
    }

    print(json.dumps(result, indent=2))

except Exception as e:
    traceback.print_exc()
    print(json.dumps({'error': str(e)}))
PYEOF

docker cp /tmp/export_audit.py wger-web:/tmp/export_audit.py
RAW_OUTPUT=$(docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/export_audit.py').read())" 2>/dev/null)
# Strip any django shell import warnings (non-JSON lines before the first '{')
DB_OUTPUT=$(echo "$RAW_OUTPUT" | python3 -c "import sys; lines=sys.stdin.read(); i=lines.find('{'); print(lines[i:] if i>=0 else '{\"error\":\"no json found\"}')")

# Wrap DB output with task timing metadata
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "elapsed_seconds": $(( TASK_END - TASK_START )),
    "db_state": $DB_OUTPUT
}
EOF

chmod 666 /tmp/task_result.json

echo "Results saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete: quarterly_audit_restructure ==="
