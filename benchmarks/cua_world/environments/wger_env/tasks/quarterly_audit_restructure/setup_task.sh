#!/bin/bash
# Task setup: quarterly_audit_restructure
# Seeds a comprehensive client profile (weight history, measurements,
# training routine with exercises, nutrition plan with meals) and writes
# the audit report document the agent must follow.

source /workspace/scripts/task_utils.sh

chmod +x /workspace/tasks/quarterly_audit_restructure/export_result.sh

echo "=== Setting up quarterly_audit_restructure task ==="

wait_for_wger_page

# ---------------------------------------------------------------------------
# Delete stale outputs from any previous run
# ---------------------------------------------------------------------------
rm -f /tmp/task_result.json /tmp/quarterly_audit_result.json
rm -f /tmp/task_start_time.txt /tmp/task_end_time.txt
rm -f /tmp/quarterly_audit_baselines.json
rm -f /tmp/task_initial.png /tmp/task_final.png

# Record task start time (anti-gaming timestamp)
date +%s > /tmp/task_start_time.txt

# ---------------------------------------------------------------------------
# Seed all task data via a single Django ORM script
# ---------------------------------------------------------------------------
cat > /tmp/setup_audit.py << 'PYEOF'
import datetime, json, traceback

from django.contrib.auth.models import User
from wger.weight.models import WeightEntry
from wger.manager.models import Routine, Day, Slot, SlotEntry, SetsConfig, RepetitionsConfig
from wger.exercises.models import Exercise, Translation, ExerciseCategory
from wger.nutrition.models import NutritionPlan, Meal, MealItem, Ingredient
from wger.measurements.models import Category as MeasureCategory, Measurement as MeasureEntry
from wger.core.models import Language

try:
    admin = User.objects.get(username='admin')
    en = Language.objects.get(short_name='en')
    today = datetime.date.today()

    # ================================================================
    # CLEANUP — remove artifacts from previous runs
    # ================================================================

    # Weight: delete ALL admin weight entries for a clean slate
    WeightEntry.objects.filter(user=admin).delete()

    # Routines: delete task-specific routine names
    for rname in ['Hypertrophy Block A', 'Strength-Power Phase B']:
        Routine.objects.filter(user=admin, name__icontains=rname).delete()

    # Nutrition plans: delete task-specific plans
    for pdesc in ['Maintenance Phase', 'Competition Peak Nutrition']:
        NutritionPlan.objects.filter(user=admin, description=pdesc).delete()

    # Measurement categories: delete task-specific categories
    for cname in ['Body Fat Percentage', 'Chest Circumference', 'Waist Circumference']:
        MeasureCategory.objects.filter(user=admin, name=cname).delete()

    print("CLEANUP: done")

    # ================================================================
    # SEED WEIGHT ENTRIES (12 entries, 2 with deliberate errors)
    # ================================================================
    weight_data = [
        ('2025-12-29', 88.2),
        ('2026-01-05', 87.8),
        ('2026-01-12', 87.4),   # ERROR: should be 87.3 (transcription)
        ('2026-01-19', 87.1),
        ('2026-01-26', 86.8),
        ('2026-02-02', 86.5),
        ('2026-02-09', 86.0),
        ('2026-02-16', 85.8),
        ('2026-02-23', 85.5),
        ('2026-03-02', 85.2),
        ('2026-03-09', 84.9),
        ('2026-03-16', 186.4),  # ERROR: entered in pounds, should be 84.6 kg
    ]
    for date_str, weight in weight_data:
        y, m, d = map(int, date_str.split('-'))
        WeightEntry.objects.create(
            user=admin,
            date=datetime.date(y, m, d),
            weight=weight
        )
    print(f"WEIGHT: created {len(weight_data)} entries")

    # ================================================================
    # SEED MEASUREMENT CATEGORIES (3 categories, 4 entries each)
    # ================================================================
    meas_dates = [
        datetime.date(2026, 2, 24),
        datetime.date(2026, 3, 3),
        datetime.date(2026, 3, 10),
        datetime.date(2026, 3, 17),
    ]

    cat_bf = MeasureCategory.objects.create(name='Body Fat Percentage', unit='%', user=admin)
    for dt, val in zip(meas_dates, [18.2, 17.8, 17.5, 17.1]):
        MeasureEntry.objects.create(category=cat_bf, date=dt, value=val)

    cat_chest = MeasureCategory.objects.create(name='Chest Circumference', unit='cm', user=admin)
    for dt, val in zip(meas_dates, [101.5, 101.8, 102.0, 102.3]):
        MeasureEntry.objects.create(category=cat_chest, date=dt, value=val)

    cat_waist = MeasureCategory.objects.create(name='Waist Circumference', unit='cm', user=admin)
    for dt, val in zip(meas_dates, [84.0, 83.5, 83.2, 82.8]):
        MeasureEntry.objects.create(category=cat_waist, date=dt, value=val)

    print("MEASUREMENTS: created 3 categories with 4 entries each")

    # ================================================================
    # ENSURE ALL EXERCISES EXIST (via Translation model)
    # ================================================================
    default_cat = ExerciseCategory.objects.get(id=9)  # Legs as fallback

    def get_or_create_ex(exact_name, cat_id=9):
        """Find exercise by exact English name, or create one."""
        t = Translation.objects.filter(name=exact_name, language=en).first()
        if t:
            return t.exercise
        # Fallback: icontains search
        t = Translation.objects.filter(name__icontains=exact_name, language=en).first()
        if t:
            return t.exercise
        # Create new exercise + English translation
        cat = ExerciseCategory.objects.get(id=cat_id)
        ex = Exercise.objects.create(category=cat)
        Translation.objects.create(exercise=ex, name=exact_name, language=en)
        return ex

    # Exercises for the existing routine
    bench       = get_or_create_ex('Bench Press', 11)
    ohp         = get_or_create_ex('Overhead Press', 13)
    triceps_ext = get_or_create_ex('Triceps Extension', 8)
    squat       = get_or_create_ex('Barbell Squat', 9)
    leg_ext     = get_or_create_ex('Leg Extension', 9)
    calf_raise  = get_or_create_ex('Standing Calf Raises', 14)
    row         = get_or_create_ex('Bent Over Barbell Row', 12)
    curl        = get_or_create_ex('Bicep Curls', 8)
    lat_raise   = get_or_create_ex('Dumbbell Lateral Raise', 13)
    deadlift    = get_or_create_ex('Deadlift', 12)
    mil_press   = get_or_create_ex('Military Press', 13)
    lunge       = get_or_create_ex('Lunges', 9)

    # Exercises the agent will need to ADD (ensure they exist for search)
    get_or_create_ex('Incline Dumbbell Press', 11)
    get_or_create_ex('Romanian Deadlift', 9)
    get_or_create_ex('Pull-ups', 12)
    get_or_create_ex('Power Clean', 9)
    get_or_create_ex('Kettlebell Swing', 15)

    # Ingredients the agent will need to FIND for the new meal
    Ingredient.objects.get_or_create(
        name='Banana, raw',
        defaults={'language': en,
                  'energy': 89, 'protein': 1.1,
                  'carbohydrates': 22.8, 'fat': 0.3}
    )

    print("EXERCISES + INGREDIENTS: ensured all exist")

    # ================================================================
    # Helper: add an exercise to a day with sets x reps config
    # ================================================================
    def add_exercise_to_day(day, exercise, order, num_sets, num_reps):
        slot = Slot.objects.create(day=day, order=order)
        se = SlotEntry.objects.create(slot=slot, exercise=exercise, order=1)
        SetsConfig.objects.create(slot_entry=se, value=num_sets, iteration=1)
        RepetitionsConfig.objects.create(slot_entry=se, value=num_reps, iteration=1)
        return se

    # ================================================================
    # SEED TRAINING ROUTINE with 4 days
    # ================================================================
    r = Routine.objects.create(
        name='Hypertrophy Block A',
        user=admin,
        description='12-week hypertrophy mesocycle for Alex Mercer',
        start=today - datetime.timedelta(weeks=12),
        end=today + datetime.timedelta(weeks=2),
    )

    # Day 1: Upper Push
    d1 = Day.objects.create(routine=r, name='Upper Push',
                            description='Upper body push focus', order=1)
    add_exercise_to_day(d1, bench, 1, 4, 8)
    add_exercise_to_day(d1, ohp, 2, 3, 10)
    add_exercise_to_day(d1, triceps_ext, 3, 3, 12)

    # Day 2: Lower Body
    d2 = Day.objects.create(routine=r, name='Lower Body',
                            description='Lower body compound movements', order=2)
    add_exercise_to_day(d2, squat, 1, 4, 8)
    add_exercise_to_day(d2, leg_ext, 2, 3, 12)
    add_exercise_to_day(d2, calf_raise, 3, 3, 15)

    # Day 3: Upper Pull
    d3 = Day.objects.create(routine=r, name='Upper Pull',
                            description='Upper body pull focus', order=3)
    add_exercise_to_day(d3, row, 1, 4, 8)
    add_exercise_to_day(d3, curl, 2, 3, 12)
    add_exercise_to_day(d3, lat_raise, 3, 3, 15)

    # Day 4: Full Body (to be deleted by agent)
    d4 = Day.objects.create(routine=r, name='Full Body',
                            description='Full body session', order=4)
    add_exercise_to_day(d4, deadlift, 1, 3, 5)
    add_exercise_to_day(d4, mil_press, 2, 3, 10)
    add_exercise_to_day(d4, lunge, 3, 3, 12)

    print(f"ROUTINE: created 'Hypertrophy Block A' (ID={r.id}) with 4 days")

    # ================================================================
    # SEED NUTRITION PLAN with goals and 3 meals
    # ================================================================
    plan = NutritionPlan.objects.create(
        user=admin,
        description='Maintenance Phase',
        only_logging=False,
        goal_energy=2800,
        goal_protein=160,
        goal_carbohydrates=340,
        goal_fat=85,
        has_goal_calories=True,
    )

    # Create ingredients (get_or_create to avoid duplicates)
    oats, _   = Ingredient.objects.get_or_create(
        name='Rolled Oats', defaults={'language': en,
        'energy': 379, 'protein': 13, 'carbohydrates': 68, 'fat': 6.5})
    milk, _   = Ingredient.objects.get_or_create(
        name='Whole Milk', defaults={'language': en,
        'energy': 61, 'protein': 3.2, 'carbohydrates': 4.7, 'fat': 3.3})
    whey, _   = Ingredient.objects.get_or_create(
        name='Whey Protein Powder', defaults={'language': en,
        'energy': 400, 'protein': 80, 'carbohydrates': 8, 'fat': 4})
    chicken, _ = Ingredient.objects.get_or_create(
        name='Chicken Breast Raw', defaults={'language': en,
        'energy': 120, 'protein': 22, 'carbohydrates': 0, 'fat': 2.6})
    rice, _   = Ingredient.objects.get_or_create(
        name='Brown Rice Cooked', defaults={'language': en,
        'energy': 123, 'protein': 2.7, 'carbohydrates': 25.6, 'fat': 1})
    broccoli, _ = Ingredient.objects.get_or_create(
        name='Broccoli Raw', defaults={'language': en,
        'energy': 34, 'protein': 2.8, 'carbohydrates': 6.6, 'fat': 0.4})
    steak, _  = Ingredient.objects.get_or_create(
        name='Beef Steak Raw', defaults={'language': en,
        'energy': 271, 'protein': 26, 'carbohydrates': 0, 'fat': 18})
    sweet_pot, _ = Ingredient.objects.get_or_create(
        name='Sweet Potato Raw', defaults={'language': en,
        'energy': 86, 'protein': 1.6, 'carbohydrates': 20.1, 'fat': 0.1})

    # Breakfast
    m1 = Meal.objects.create(plan=plan, name='Breakfast', order=1)
    MealItem.objects.create(meal=m1, ingredient=oats, amount=80, order=1)
    MealItem.objects.create(meal=m1, ingredient=milk, amount=250, order=2)
    MealItem.objects.create(meal=m1, ingredient=whey, amount=30, order=3)

    # Lunch
    m2 = Meal.objects.create(plan=plan, name='Lunch', order=2)
    MealItem.objects.create(meal=m2, ingredient=chicken, amount=200, order=1)
    MealItem.objects.create(meal=m2, ingredient=rice, amount=150, order=2)
    MealItem.objects.create(meal=m2, ingredient=broccoli, amount=100, order=3)

    # Dinner (to be deleted by agent)
    m3 = Meal.objects.create(plan=plan, name='Dinner', order=3)
    MealItem.objects.create(meal=m3, ingredient=steak, amount=250, order=1)
    MealItem.objects.create(meal=m3, ingredient=sweet_pot, amount=200, order=2)

    print(f"NUTRITION: created 'Maintenance Phase' (ID={plan.id}) with 3 meals")

    # ================================================================
    # RECORD BASELINE STATE
    # ================================================================
    baselines = {
        'routine_id': r.id,
        'plan_id': plan.id,
        'weight_entry_count': WeightEntry.objects.filter(user=admin).count(),
        'routine_count': Routine.objects.filter(user=admin).count(),
        'nutrition_plan_count': NutritionPlan.objects.filter(user=admin).count(),
        'measurement_category_count': MeasureCategory.objects.filter(user=admin).count(),
    }
    with open('/tmp/quarterly_audit_baselines.json', 'w') as f:
        json.dump(baselines, f)

    print(f"BASELINES: {json.dumps(baselines)}")
    print("SETUP_SUCCESS")

except Exception as e:
    traceback.print_exc()
    print(f"SETUP_ERROR: {e}")
PYEOF

docker cp /tmp/setup_audit.py wger-web:/tmp/setup_audit.py
SETUP_OUT=$(docker exec wger-web python3 manage.py shell -c "exec(open('/tmp/setup_audit.py').read())" 2>&1)
echo "$SETUP_OUT"

if echo "$SETUP_OUT" | grep -q "SETUP_SUCCESS"; then
    echo "Database seeding successful"
else
    echo "WARNING: Database seeding may have failed. Output above."
fi

# ---------------------------------------------------------------------------
# Write the companion audit report document
# ---------------------------------------------------------------------------
mkdir -p /home/ga/Documents

cat > /home/ga/Documents/quarterly_audit_report.txt << 'DOCEOF'
================================================================
MERIDIAN ATHLETICS — QUARTERLY PROGRAM AUDIT REPORT
Client: Alex Mercer | Coach: You | Quarter: Q1 2026
================================================================

SECTION A — WEIGHT LOG CORRECTIONS
-----------------------------------
Two entries in the client's weight log require correction:

1. Entry dated 2026-01-12 currently reads 87.4 kg.
   Correct value: 87.3 kg (transcription rounding error
   from digital scale readout 87.32).

2. Entry dated 2026-03-16 currently reads 186.4 kg.
   This was recorded in pounds instead of kilograms.
   Correct value: 84.6 kg.

After corrections the most recent body weight is 84.6 kg.
This value is used for nutrition calculations in Section D.

SECTION B — NEW BODY COMPOSITION MEASUREMENTS
----------------------------------------------
Record the following values from today's quarterly assessment
into the existing measurement categories:

  Body Fat Percentage:   16.8 %
  Chest Circumference:  102.8 cm
  Waist Circumference:   82.3 cm

SECTION C — TRAINING ROUTINE RESTRUCTURE
-----------------------------------------
The existing routine is named "Hypertrophy Block A".

1. Rename the routine to "Strength-Power Phase B".

2. Remove the "Full Body" training day entirely.
   The athlete is transitioning to a focused split.

3. Modify the "Upper Push" day:
   - Remove Overhead Press.
   - Add Incline Dumbbell Press, 3 sets x 10 reps.
   - Keep Bench Press and Triceps Extension unchanged.

4. Modify the "Lower Body" day:
   - Add Romanian Deadlift, 3 sets x 10 reps.
   - Keep all existing exercises unchanged.

5. Add a new training day named "Explosive Power"
   assigned to Wednesday, with these exercises:
   - Pull-ups, 4 sets x 6 reps
   - Power Clean, 5 sets x 3 reps
   - Kettlebell Swing, 3 sets x 15 reps

SECTION D — NUTRITION PLAN ADJUSTMENTS
---------------------------------------
Update the daily macro goals on the "Maintenance Phase"
nutrition plan using the corrected current body weight
(84.6 kg) and these multipliers:

  Protein  = 2.2 g/kg x 84.6 = 186 g
  Carbs    = 4.5 g/kg x 84.6 = 381 g
  Fat      = 1.0 g/kg x 84.6 =  85 g
  Energy   = (186x4) + (381x4) + (85x9) = 3033 kcal

Also make these meal changes on the same plan:

  - Remove the "Dinner" meal (athlete is switching to
    intermittent fasting; last meal is lunch).
  - Add a new meal "Post-Workout Recovery" containing:
      Whey Protein Powder  40 g
      Banana              120 g

SECTION E — COMPETITION PHASE NUTRITION PLAN
---------------------------------------------
Create a new nutrition plan named "Competition Peak Nutrition"
with these daily goals:

  Energy  = 2400 kcal
  Protein =  200 g
  Carbs   =  220 g
  Fat     =   70 g

Add three meals (names only; items will be added later
by the sport dietitian):
  1. Pre-Weigh-In Breakfast
  2. Post-Weigh-In Recovery
  3. Pre-Competition Fuel

================================================================
END OF AUDIT REPORT
================================================================
DOCEOF

chown ga:ga /home/ga/Documents/quarterly_audit_report.txt 2>/dev/null || true
echo "Audit report written to /home/ga/Documents/quarterly_audit_report.txt"

# ---------------------------------------------------------------------------
# Launch Firefox to the wger dashboard
# ---------------------------------------------------------------------------
launch_firefox_to "http://localhost/en/dashboard" 5

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete: quarterly_audit_restructure ==="
